// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.abs

sealed interface VideoState {
    data object None : VideoState
    data class Receiving(val progress: Double) : VideoState
    data object Ready : VideoState
    data class Failed(val reason: String) : VideoState
}

/** Gets the video from the editor and plays it on the shared clock. */
class CompanionVideo(private val context: Context) {
    var state: VideoState by mutableStateOf(VideoState.None)
        private set
    var player: ExoPlayer? by mutableStateOf(null)
        private set
    private var sound by mutableStateOf(false)
    var soundOn: Boolean
        get() = sound
        set(value) { sound = value; player?.volume = if (value) 1f else 0f }

    var onReady: ((String) -> Unit)? = null
    var onFailed: ((String, String) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var id: String? = null
    private var size = 0L
    private var written = 0L
    private var out: FileOutputStream? = null
    private var file: File? = null
    private var lastShown = -1.0
    private val startRunnable = Runnable { player?.play() }

    // MARK: Receive. Called on the connection thread.

    fun begin(id: String, name: String, size: Long) {
        clear()
        synchronized(lock) {
            this.id = id
            this.size = size
            written = 0
            lastShown = -1.0
            val ext = name.substringAfterLast('.', "mp4")
            val f = File(context.cacheDir, "feel-${UUID.randomUUID()}.$ext")
            try {
                out = FileOutputStream(f)
                file = f
            } catch (_: Exception) {
                fail("Cannot store video.")
                return
            }
        }
        main.post { state = VideoState.Receiving(0.0) }
    }

    fun append(id: String, offset: Long, data: ByteArray) {
        synchronized(lock) {
            val o = out ?: return
            if (id != this.id || offset != written) return
            try {
                o.write(data)
                written += data.size
            } catch (_: Exception) {
                fail("Out of space.")
                return
            }
            val p = written.toDouble() / maxOf(size, 1)
            if (p - lastShown >= 0.01) {
                lastShown = p
                main.post { state = VideoState.Receiving(p) }
            }
        }
    }

    fun finish(id: String) {
        val f: File
        synchronized(lock) {
            if (id != this.id) return
            val o = out ?: return
            try { o.close() } catch (_: Exception) {}
            out = null
            if (written != size) { fail("Video transfer incomplete."); return }
            f = file ?: return
        }
        main.post {
            val p = ExoPlayer.Builder(context).build()
            p.setSeekParameters(SeekParameters.EXACT)
            p.volume = if (soundOn) 1f else 0f
            p.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(f)))
            p.prepare()
            player?.release()
            player = p
            state = VideoState.Ready
            onReady?.invoke(id)
        }
    }

    private fun fail(reason: String) {
        val failed = id
        clearLocked()
        main.post { state = VideoState.Failed(reason) }
        if (failed != null) onFailed?.invoke(failed, reason)
    }

    fun clear() {
        synchronized(lock) { clearLocked() }
        main.post {
            main.removeCallbacks(startRunnable)
            player?.release()
            player = null
            state = VideoState.None
        }
    }

    private fun clearLocked() {
        try { out?.close() } catch (_: Exception) {}
        out = null
        file?.delete()
        file = null
        id = null
        written = 0
    }

    // MARK: Playback. Main thread.

    /** Media time `mediaTime` plays at editor host time `hostTime`. */
    fun play(mediaTime: Double, hostTime: Double, clockOffset: Double) {
        val p = player ?: return
        if (state != VideoState.Ready) return
        main.removeCallbacks(startRunnable)
        val now = SharedClock.now()
        val startLocal = hostTime - clockOffset
        if (startLocal > now + 0.02) {
            // Start is ahead. Park on the first frame, then release at the shared instant.
            p.pause()
            p.seekTo((mediaTime * 1000).toLong())
            main.postDelayed(startRunnable, ((startLocal - now) * 1000).toLong())
            return
        }
        val position = mediaTime + (now - startLocal)
        val drift = abs(p.currentPosition / 1000.0 - position)
        if (!p.isPlaying || drift > 0.08) {
            p.seekTo(((position + 0.05) * 1000).toLong())
            p.play()
        }
    }

    fun pause(at: Double) {
        val p = player ?: return
        main.removeCallbacks(startRunnable)
        p.pause()
        p.seekTo((at * 1000).toLong())
    }

    fun release() {
        clear()
    }
}
