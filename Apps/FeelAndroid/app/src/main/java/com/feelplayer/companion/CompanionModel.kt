// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.concurrent.thread
import kotlin.math.abs

/** The Android companion. Same job as the iPhone app: pair, take haptics and video, follow the editor's clock. */
class CompanionModel(private val context: Context) : PlayerTransport {
    var editorName: String? by mutableStateOf(null)
        private set
    /** Name of the Mac while a connection attempt runs. */
    var connecting: String? by mutableStateOf(null)
        private set
    var error: String? by mutableStateOf(null)
        private set
    var macs: List<Mac> by mutableStateOf(emptyList())
        private set
    override var isPlaying by mutableStateOf(false)
        private set
    override var mediaTime by mutableDoubleStateOf(0.0)
        private set
    override var duration by mutableDoubleStateOf(0.0)
        private set
    var rtt: Double? by mutableStateOf(null)
        private set
    var notice: String? by mutableStateOf(null)
        private set
    var eventCount by mutableIntStateOf(0)
        private set
    var debugLine by mutableStateOf("")
        private set

    /** How hard the haptic under the playhead hits, 0..1. For display only. */
    val hapticLevel: Double
        get() {
            if (!isPlaying) return 0.0
            val t = mediaTime
            return events.maxOfOrNull { it.level(t) } ?: 0.0
        }

    val deviceName: String = Settings.Global.getString(context.contentResolver, "device_name") ?: Build.MODEL
    val haptics = HapticPlayer(context)
    val video = CompanionVideo(context)

    private val main = Handler(Looper.getMainLooper())
    private var browser: MacBrowser? = null
    private var target: JoinLink? = null
    private var userClosed = false
    private var everConnected = false
    private var attempts = 0
    private var connection: FeelConnection? = null
    private val clock = ClockSync()
    private var events: List<HapticEvent> by mutableStateOf(emptyList())
    override val hapticGraph by derivedStateOf { HapticGraph.levels(events, duration) }
    private var revision = -1
    private var transport: Transport? = null
    private var pingThread: Thread? = null
    private var nextPing = 0
    private val window = 10.0

    private data class Transport(val mediaTime: Double, val hostTime: Double, val advance: Double)

    private val windowRunnable = Runnable { reschedule() }
    private val uiRunnable = object : Runnable {
        override fun run() {
            val t = transport
            val off = clock.offset
            if (t != null && off != null) {
                mediaTime = maxOf(PlaybackPlan.position(t.mediaTime, t.hostTime, t.advance, off, SharedClock.now()) + t.advance, 0.0)
                main.postDelayed(this, 33)
            }
        }
    }

    init {
        video.onReady = { id -> connection?.send(Wire.videoReady(id)) }
        video.onFailed = { id, reason -> connection?.send(Wire.videoFailed(id, reason)) }
    }

    // MARK: Lifecycle

    fun start() {
        if (!haptics.supportsHaptics) notice = "This device has no vibration motor."
        if (browser == null) {
            browser = MacBrowser(context) { list -> main.post { macs = list } }.also { it.start() }
        }
    }

    fun stop() {
        userClosed = true
        dropConnection()
        browser?.stop()
        browser = null
    }

    /** From a QR code, a link, or a Mac picked from the list. */
    fun connect(link: JoinLink) {
        userClosed = false
        everConnected = false
        attempts = 0
        error = null
        target = link
        open(link)
    }

    fun fail(message: String) { error = message }

    fun cancelConnecting() { disconnect() }

    fun connect(mac: Mac, code: String) = connect(JoinLink(mac.host, mac.port, code, mac.name))

    private fun open(link: JoinLink) {
        connection?.close()
        connecting = link.name
        val conn = FeelConnection(link.host, link.port, link.code)
        connection = conn
        clock.reset()
        rtt = null
        // New editor session. Its revision numbers start over.
        revision = -1
        events = emptyList()
        eventCount = 0
        conn.onMessage = { msg, stamp -> handle(msg, stamp, conn) }
        conn.onReady = {
            conn.send(Wire.hello(deviceName, haptics.supportsHaptics))
            startPinging(conn)
        }
        conn.onClosed = { reached -> main.post { if (conn === connection) connectionLost(reached) } }
        conn.start()
    }

    private fun connectionLost(reachedReady: Boolean) {
        dropConnection()
        val t = target
        if (userClosed || t == null) return
        if (reachedReady) everConnected = true
        if (everConnected && attempts < 6) {
            // Lost a good link. Try again with backoff.
            attempts += 1
            connecting = t.name
            val delay = minOf(1L shl (attempts - 1), 15L) * 1000
            main.postDelayed({ if (!userClosed && connection == null) open(t) }, delay)
        } else {
            connecting = null
            error = "Could not connect. Check the code and that both devices share Wi-Fi."
        }
    }

    fun disconnect() {
        userClosed = true
        connection?.send(Wire.bye())
        dropConnection()
        connecting = null
        target = null
    }

    private fun dropConnection() {
        pingThread?.interrupt()
        main.removeCallbacks(windowRunnable)
        main.removeCallbacks(uiRunnable)
        connection?.close()
        connection = null
        haptics.stop()
        video.clear()
        transport = null
        isPlaying = false
        editorName = null
        duration = 0.0
        rtt = null
    }

    // MARK: Messages. Reader thread. Video bytes stay off the main thread.

    private fun handle(msg: Incoming, stamp: Double, conn: FeelConnection) {
        when (msg) {
            is Incoming.VideoOffer -> video.begin(msg.id, msg.name, msg.size)
            is Incoming.VideoChunk -> video.append(msg.id, msg.offset, msg.data)
            is Incoming.VideoEnd -> video.finish(msg.id)
            else -> main.post { if (conn === connection) handleMain(msg, stamp) }
        }
    }

    private fun handleMain(msg: Incoming, stamp: Double) {
        when (msg) {
            is Incoming.Hello -> { editorName = msg.name; connecting = null; error = null; attempts = 0; everConnected = true; sendStatus() }
            is Incoming.Pong -> { clock.add(msg.t0, msg.t1, msg.t2, stamp); rtt = clock.rtt }
            is Incoming.Pattern -> {
                if (msg.revision <= revision) return
                revision = msg.revision
                events = msg.events
                eventCount = msg.events.size
                if (isPlaying) reschedule()
            }
            is Incoming.Play -> applyPlay(Transport(msg.mediaTime, msg.hostTime, msg.advance))
            is Incoming.Pause -> {
                transport = null
                isPlaying = false
                main.removeCallbacks(windowRunnable)
                main.removeCallbacks(uiRunnable)
                haptics.stop()
                video.pause(msg.mediaTime)
                mediaTime = msg.mediaTime
                sendStatus()
            }
            // One motor. An audition would cancel the scheduled window until the next one starts.
            is Incoming.Audition -> if (!isPlaying) haptics.audition(msg.event)
            is Incoming.VideoClear -> video.clear()
            is Incoming.Timeline -> duration = msg.duration
            is Incoming.Bye -> { userClosed = true; dropConnection(); target = null }
            else -> {}
        }
    }

    // MARK: Clock sync

    private fun startPinging(conn: FeelConnection) {
        pingThread?.interrupt()
        pingThread = thread(name = "feel-ping", isDaemon = true) {
            var burst = 0
            try {
                while (true) {
                    nextPing += 1
                    conn.send(Wire.ping(nextPing, SharedClock.now()))
                    burst += 1
                    main.post { if (conn === connection) sendStatus() }
                    Thread.sleep(if (burst < 12) 120 else 2000)
                }
            } catch (_: InterruptedException) {}
        }
    }

    private fun sendStatus() {
        val line = "windows ${haptics.windowsPlayed} · pieces ${haptics.lastItems} · amp ${if (haptics.hasAmplitudeControl) "yes" else "no"}"
        debugLine = line
        connection?.send(Wire.status(isPlaying, haptics.supportsHaptics, rtt, notice))
    }

    // MARK: Playback

    private fun applyPlay(new: Transport) {
        val off = clock.offset ?: return // wait for the first pong. The editor resends.
        val now = SharedClock.now()
        video.play(new.mediaTime, new.hostTime, off)
        val old = transport
        if (isPlaying && old != null) {
            val a = PlaybackPlan.position(old.mediaTime, old.hostTime, old.advance, off, now)
            val b = PlaybackPlan.position(new.mediaTime, new.hostTime, new.advance, off, now)
            if (abs(a - b) < 0.04) { transport = new; return }
        }
        transport = new
        isPlaying = true
        reschedule()
        main.removeCallbacks(uiRunnable)
        main.post(uiRunnable)
        sendStatus()
    }

    /** Cancel and rebuild the haptics for the next window from the current transport and clock. */
    private fun reschedule() {
        main.removeCallbacks(windowRunnable)
        val t = transport ?: return
        val off = clock.offset ?: return
        val plan = PlaybackPlan.make(t.mediaTime, t.hostTime, t.advance, off, SharedClock.now())
        haptics.play(events, plan.mediaStart, plan.mediaStart + window, plan.delay)
        // Next window starts shortly before this one ends.
        main.postDelayed(windowRunnable, ((window - 1.5 + plan.delay) * 1000).toLong())
    }

    // MARK: Remote control

    override fun togglePlay() {
        connection?.send(if (isPlaying) Wire.remotePause() else Wire.remotePlay())
    }

    override fun seek(to: Double, final: Boolean) {
        val t = to.coerceIn(0.0, duration)
        mediaTime = t
        if (!isPlaying || final) video.pause(t)
        connection?.send(Wire.remoteSeek(t, final))
    }

    fun testHaptic() {
        haptics.audition(HapticEvent(type = "tap", start = 0.0, intensity = 1.0, sharpness = 0.8))
        main.postDelayed({
            haptics.audition(HapticEvent(type = "rumble", start = 0.0, duration = 0.6, intensity = 0.7, sharpness = 0.3, fadeIn = 0.1, fadeOut = 0.3))
        }, 250)
    }
}
