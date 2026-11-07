// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import org.bouncycastle.tls.BasicTlsPSKIdentity
import org.bouncycastle.tls.CipherSuite
import org.bouncycastle.tls.PSKTlsClient
import org.bouncycastle.tls.ProtocolVersion
import org.bouncycastle.tls.TlsClientProtocol
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import kotlin.concurrent.thread

object Pairing {
    /** Key both sides derive from the code. Matches the Mac and iPhone apps. */
    fun key(code: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest("feel-haptics-v1:$code".toByteArray(Charsets.UTF_8))
}

/** What the Mac's QR code holds: feel://join?host=..&port=..&code=..&name=.. */
data class JoinLink(val host: String, val port: Int, val code: String, val name: String) {
    companion object {
        fun parse(text: String?): JoinLink? {
            val u = try { android.net.Uri.parse(text ?: return null) } catch (_: Exception) { return null }
            if (u.scheme != "feel" || u.host != "join") return null
            val host = u.getQueryParameter("host") ?: return null
            val port = u.getQueryParameter("port")?.toIntOrNull() ?: return null
            val code = u.getQueryParameter("code") ?: return null
            if (code.length != 6) return null
            return JoinLink(host, port, code, u.getQueryParameter("name") ?: host)
        }
    }
}

/** TLS 1.2 with a pre-shared key. A wrong code fails the handshake. */
private class PskClient(code: String) : PSKTlsClient(
    BcTlsCrypto(SecureRandom()),
    BasicTlsPSKIdentity("feel".toByteArray(Charsets.UTF_8), Pairing.key(code)),
) {
    override fun getSupportedCipherSuites(): IntArray = intArrayOf(CipherSuite.TLS_PSK_WITH_AES_128_GCM_SHA256)
    override fun getSupportedVersions(): Array<ProtocolVersion> = ProtocolVersion.TLSv12.only()
}

/** One link to the Mac. Connects out, then reads on its own thread. Messages carry the clock time taken at receipt. */
class FeelConnection(private val host: String, private val port: Int, private val code: String) {
    var onMessage: ((Incoming, Double) -> Unit)? = null
    var onReady: (() -> Unit)? = null
    var onClosed: ((reachedReady: Boolean) -> Unit)? = null

    @Volatile private var out: OutputStream? = null
    @Volatile private var closed = false
    @Volatile private var ready = false
    private var socket: Socket? = null

    fun start() {
        thread(name = "feel-connection", isDaemon = true) {
            try {
                val s = Socket()
                socket = s
                s.tcpNoDelay = true
                s.connect(InetSocketAddress(host, port), 5000)
                val proto = TlsClientProtocol(s.getInputStream(), s.getOutputStream())
                proto.connect(PskClient(code))
                out = proto.outputStream
                ready = true
                android.util.Log.i("Feel", "TLS ready")
                onReady?.invoke()
                readLoop(proto.inputStream)
            } catch (e: Throwable) {
                android.util.Log.w("Feel", "connection ended: $e")
            } finally {
                close()
            }
        }
    }

    private fun readLoop(input: InputStream) {
        val buf = ByteArray(64 * 1024)
        var line = java.io.ByteArrayOutputStream()
        while (!closed) {
            val n = input.read(buf)
            if (n < 0) return
            val stamp = SharedClock.now()
            var from = 0
            for (i in 0 until n) {
                if (buf[i] == '\n'.code.toByte()) {
                    line.write(buf, from, i - from)
                    from = i + 1
                    val text = line.toString(Charsets.UTF_8.name())
                    line = java.io.ByteArrayOutputStream()
                    if (text.isNotEmpty()) {
                        val msg = try { Wire.decode(text) } catch (_: Exception) { Incoming.Ignored }
                        onMessage?.invoke(msg, stamp)
                    }
                }
            }
            if (from < n) line.write(buf, from, n - from)
            if (line.size() > 16 shl 20) return
        }
    }

    /** Writes happen on one background thread, in order. Never touch the socket on the main thread. */
    private val writer = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "feel-writer").apply { isDaemon = true } }

    fun send(bytes: ByteArray) {
        if (closed) return
        try {
            writer.execute {
                val o = out ?: return@execute
                try {
                    o.write(bytes); o.flush()
                } catch (_: Exception) {
                    close()
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {}
    }

    fun close() {
        if (closed) return
        closed = true
        // Let a queued "bye" go out first.
        try { writer.shutdown(); writer.awaitTermination(300, java.util.concurrent.TimeUnit.MILLISECONDS) } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        onClosed?.invoke(ready)
    }
}

data class Mac(val name: String, val host: String, val port: Int)

/** Finds Macs on the network that run Feel. */
class MacBrowser(context: Context, private val onUpdate: (List<Mac>) -> Unit) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val found = LinkedHashMap<String, Mac>()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var listener: NsdManager.DiscoveryListener? = null

    fun start() {
        if (listener != null) return
        val l = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) {}
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onServiceFound(info: NsdServiceInfo) { synchronized(this@MacBrowser) { queue.add(info) }; next() }
            override fun onServiceLost(info: NsdServiceInfo) {
                synchronized(this@MacBrowser) { found.remove(info.serviceName); publish() }
            }
        }
        listener = l
        nsd.discoverServices("_feelhaptics._tcp", NsdManager.PROTOCOL_DNS_SD, l)
    }

    fun stop() {
        listener?.let { try { nsd.stopServiceDiscovery(it) } catch (_: Exception) {} }
        listener = null
    }

    @Synchronized private fun publish() { onUpdate(found.values.toList()) }

    private fun next() {
        val info: NsdServiceInfo
        synchronized(this) {
            if (resolving) return
            info = queue.removeFirstOrNull() ?: return
            resolving = true
        }
        @Suppress("DEPRECATION")
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(i: NsdServiceInfo, code: Int) { done() }
            override fun onServiceResolved(i: NsdServiceInfo) {
                val addr = if (Build.VERSION.SDK_INT >= 34) {
                    i.hostAddresses.firstOrNull { it is java.net.Inet4Address } ?: i.hostAddresses.firstOrNull()
                } else {
                    @Suppress("DEPRECATION") i.host
                }
                val host = addr?.hostAddress?.substringBefore('%')
                // Only editors. Older builds of the phone apps also advertise, and must not be listed.
                val isEditor = i.attributes["role"]?.let { String(it, Charsets.UTF_8) } == "editor"
                if (host != null && isEditor) synchronized(this@MacBrowser) { found[i.serviceName] = Mac(i.serviceName, host, i.port); publish() }
                done()
            }
        })
    }

    private fun done() {
        synchronized(this) { resolving = false }
        next()
    }
}
