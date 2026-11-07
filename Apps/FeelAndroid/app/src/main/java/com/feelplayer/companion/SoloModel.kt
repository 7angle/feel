// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Log
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import kotlin.concurrent.thread

/** Plays a video from this phone with haptics. No Mac needed. Main thread only. */
class SoloModel(private val context: Context, private val haptics: HapticPlayer) : PlayerTransport {
    var player: ExoPlayer? by mutableStateOf(null)
        private set
    var name by mutableStateOf("")
        private set
    override var duration by mutableDoubleStateOf(0.0)
        private set
    override var mediaTime by mutableDoubleStateOf(0.0)
        private set
    /** The user wants it playing. Follows the button at once, before the player starts. */
    override var isPlaying by mutableStateOf(false)
        private set
    var aspect by mutableFloatStateOf(16f / 9f)
        private set
    var events: List<HapticEvent> by mutableStateOf(emptyList())
        private set
    var isMaking by mutableStateOf(false)
        private set
    override val hapticGraph by derivedStateOf { HapticGraph.levels(events, duration) }
    var message: String? by mutableStateOf(null)
    var warning: String? by mutableStateOf(null)
        private set
    private var sound by mutableStateOf(true)
    var soundOn: Boolean
        get() = sound
        set(value) { sound = value; player?.volume = if (value) 1f else 0f }

    private val main = Handler(Looper.getMainLooper())
    private var videoUri: Uri? = null
    /** Each analysis has a number. A newer video or file makes the old result worthless. */
    @Volatile private var analysis = 0L
    private var resumeAfterSeek = false

    private val tick = object : Runnable {
        override fun run() {
            val p = player ?: return
            mediaTime = minOf(p.currentPosition / 1000.0, duration)
            main.postDelayed(this, 33)
        }
    }
    private val nextWindow = Runnable { schedule() }

    private val listener = object : Player.Listener {
        override fun onTracksChanged(tracks: Tracks) {
            if (tracks.isEmpty) return
            if (!tracks.containsType(C.TRACK_TYPE_VIDEO)) {
                refuse("This file has no picture.")
            } else if (!tracks.isTypeSupported(C.TRACK_TYPE_VIDEO, true)) {
                refuse("This phone cannot show ${codecName(tracks)} video. Use an H.264 or HEVC file (MP4 or MOV).")
            }
        }

        override fun onPlaybackStateChanged(state: Int) {
            val p = player ?: return
            if (state == Player.STATE_READY && p.duration != C.TIME_UNSET) duration = p.duration / 1000.0
            if (state == Player.STATE_ENDED) {
                p.playWhenReady = false
                isPlaying = false
                mediaTime = duration
            }
        }

        /** Haptics follow what the player really does, so buffering stops them too. */
        override fun onIsPlayingChanged(playing: Boolean) {
            if (playing) {
                schedule()
                main.removeCallbacks(tick)
                main.post(tick)
            } else {
                stopHaptics()
                main.removeCallbacks(tick)
            }
        }

        override fun onVideoSizeChanged(size: VideoSize) {
            if (size.width > 0 && size.height > 0) aspect = size.width * size.pixelWidthHeightRatio / size.height
        }

        override fun onPlayerError(error: PlaybackException) {
            refuse("Cannot play this video.")
        }
    }

    // MARK: Open

    /** A video, or a haptics file for the open video. */
    fun open(uri: Uri) {
        val type = context.contentResolver.getType(uri)
        val fileName = displayName(uri)
        val isVideo = type?.startsWith("video/") == true ||
            fileName.substringAfterLast('.', "").lowercase() in VIDEO_EXTENSIONS
        if (isVideo) openVideo(uri, fileName) else loadHaptics(uri)
    }

    private fun openVideo(uri: Uri, fileName: String) {
        close()
        message = null
        videoUri = uri
        name = fileName.substringBeforeLast('.')
        val p = ExoPlayer.Builder(context).build()
        p.setSeekParameters(SeekParameters.EXACT)
        p.volume = if (soundOn) 1f else 0f
        p.addListener(listener)
        p.setMediaItem(MediaItem.fromUri(uri))
        p.prepare()
        player = p
        makeFromSound()
    }

    /** The sound would still play with no picture. Close it, and say why. */
    private fun refuse(reason: String) {
        close()
        message = reason
    }

    private fun codecName(tracks: Tracks): String {
        val mime = tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_VIDEO }?.getTrackFormat(0)?.sampleMimeType.orEmpty()
        return when {
            mime.contains("av01") -> "AV1"
            mime.contains("x-vnd.on2.vp9") -> "VP9"
            mime.contains("dolby-vision") -> "Dolby Vision"
            else -> "this"
        }
    }

    private fun displayName(uri: Uri): String {
        try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) return c.getString(0)
            }
        } catch (_: Exception) {}
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Video"
    }

    fun close() {
        analysis++
        isMaking = false
        main.removeCallbacks(tick)
        stopHaptics()
        player?.removeListener(listener)
        player?.release()
        player = null
        videoUri = null
        name = ""
        duration = 0.0
        mediaTime = 0.0
        isPlaying = false
        aspect = 16f / 9f
        events = emptyList()
        warning = null
        resumeAfterSeek = false
    }

    // MARK: Haptics

    private fun loadHaptics(uri: Uri) {
        if (player == null) {
            message = "Open the video first, then its haptics file."
            return
        }
        try {
            val text = context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                ?: throw HapticShare.ShareException("Cannot open that file.")
            val doc = HapticShare.decode(text)
            analysis++
            isMaking = false
            useEvents(doc.events)
            warning = when (val m = HapticShare.match(doc, duration)) {
                is HapticShare.Match.LengthDiffers ->
                    "Made for a video of ${timecode(m.expected)}. This one is ${timecode(m.actual)}. Timing may be off."
                else -> null
            }
            message = null
        } catch (e: HapticShare.ShareException) {
            message = e.message
        } catch (_: java.io.IOException) {
            message = "Cannot open that file."
        }
    }

    private fun useEvents(new: List<HapticEvent>) {
        events = new
        if (player?.isPlaying == true) schedule()
    }

    fun clearHaptics() {
        analysis++
        isMaking = false
        useEvents(emptyList())
        warning = null
        haptics.stop()
    }

    fun makeFromSound() {
        val uri = videoUri ?: return
        val id = ++analysis
        isMaking = true
        thread(name = "feel-audio", isDaemon = true, priority = Thread.NORM_PRIORITY - 1) {
            val began = SystemClock.elapsedRealtime()
            val spectrum = AudioExtractor.extract(context, uri) { analysis != id }
            val found = spectrum?.let { AudioHaptics.generate(it, 0.5) }
            Log.i("Feel", "audio haptics: ${found?.size} events from ${spectrum?.count} frames in ${SystemClock.elapsedRealtime() - began} ms")
            main.post {
                if (analysis != id) return@post
                isMaking = false
                when {
                    spectrum == null -> message = "Cannot read the sound of this video."
                    found.isNullOrEmpty() -> message = "No clear hits in the sound."
                    else -> {
                        useEvents(found)
                        warning = null
                    }
                }
            }
        }
    }

    fun testHaptic() {
        if (player?.isPlaying != true) haptics.audition(HapticEvent(type = "tap", start = 0.0, intensity = 1.0, sharpness = 0.8))
    }

    // MARK: Playback

    override fun togglePlay() { if (isPlaying) pause() else play() }

    fun play() {
        val p = player ?: return
        if (p.playbackState == Player.STATE_ENDED) { p.seekTo(0); mediaTime = 0.0 }
        p.playWhenReady = true
        isPlaying = true
    }

    fun pause() {
        val p = player ?: return
        p.playWhenReady = false
        isPlaying = false
        mediaTime = p.currentPosition / 1000.0
    }

    /** Haptics for the next window, from where the player really is. This also corrects drift. */
    private fun schedule() {
        main.removeCallbacks(nextWindow)
        val p = player ?: return
        if (!p.isPlaying) return
        val start = p.currentPosition / 1000.0 + LEAD
        haptics.play(events, start, start + WINDOW, LEAD)
        main.postDelayed(nextWindow, ((WINDOW - 1.5) * 1000).toLong())
    }

    private fun stopHaptics() {
        main.removeCallbacks(nextWindow)
        haptics.stop()
    }

    // MARK: Seek

    /** While dragging, `final` is false. Release resumes if it was playing. */
    override fun seek(to: Double, final: Boolean) {
        val p = player ?: return
        val t = to.coerceIn(0.0, maxOf(duration, 0.0))
        // Haptics are scheduled from the playhead, so a seek always restarts them.
        if (isPlaying) { resumeAfterSeek = true; pause() }
        mediaTime = t
        p.seekTo((t * 1000).toLong())
        if (final && resumeAfterSeek) { resumeAfterSeek = false; play() }
    }

    private companion object {
        val VIDEO_EXTENSIONS = setOf("mp4", "mov", "m4v", "mkv", "webm")
        /** Seconds of pattern per window, as in the companion. */
        const val WINDOW = 10.0
        /** Time for the vibrator call to land. */
        const val LEAD = 0.03
    }
}
