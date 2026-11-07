package com.feelplayer.haptics

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Plays "share-golden.json" in step with a Media3 player.
 *
 * Usage:
 *
 *     val player = ExoPlayer.Builder(context).build()
 *     val haptics = HapticVideoSync.fromAsset(context, player, "share-golden.json")
 *     player.setMediaItem(MediaItem.fromUri(videoUri))
 *     player.prepare()
 *     player.play()   // haptics follow play, pause, seek and speed changes
 *
 *     // When you are done:
 *     haptics.release()
 *     player.release()
 *
 * Put "share-golden.json" in app/src/main/assets.
 * Add <uses-permission android:name="android.permission.VIBRATE" /> to AndroidManifest.xml.
 * Keep a strong reference to `HapticVideoSync`.
 */
class HapticVideoSync(context: Context, private val player: Player, json: String) {
    private val events = FeelHaptics.parse(json)
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
        @Suppress("DEPRECATION") (context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
    }
    private val handler = Handler(player.applicationLooper)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
        .build()
    private val nextWindow = Runnable { schedule() }

    private val listener = object : Player.Listener {
        // Haptics follow what the player really does, so buffering stops them too.
        override fun onIsPlayingChanged(isPlaying: Boolean) = restart()

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) = restart()

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) = restart()
    }

    /** False when the device has no vibration motor. */
    val isSupported: Boolean get() = vibrator.hasVibrator()

    init {
        player.addListener(listener)
        restart()
    }

    /** Stop haptics and stop following the player. */
    fun release() {
        player.removeListener(listener)
        stop()
    }

    private fun stop() {
        handler.removeCallbacksAndMessages(null)
        vibrator.cancel()
    }

    private fun restart() {
        stop()
        schedule()
    }

    /** Haptics for the next window, from where the player really is. This also corrects drift. */
    private fun schedule() {
        handler.removeCallbacksAndMessages(null)
        if (!player.isPlaying) return
        val speed = player.playbackParameters.speed.toDouble()
        val start = player.currentPosition / 1000.0 + LEAD
        val wave = FeelHaptics.waveform(events, start, start + WINDOW)
        if (wave != null) {
            val timings = LongArray(wave.timings.size) { (wave.timings[it] / speed).roundToLong().coerceAtLeast(1) }
            val effect = if (vibrator.hasAmplitudeControl()) {
                VibrationEffect.createWaveform(timings, wave.amplitudes, -1)
            } else {
                VibrationEffect.createWaveform(FeelHaptics.onOffTimings(timings, wave.amplitudes), -1)
            }
            // A new effect replaces the old one. The windows overlap, so no haptic is lost at the change.
            handler.postDelayed({
                @Suppress("DEPRECATION") vibrator.vibrate(effect, attributes)
            }, (LEAD / speed * 1000).toLong())
        }
        handler.postDelayed(nextWindow, ((WINDOW - OVERLAP) / speed * 1000).toLong())
    }

    companion object {
        // Short, so haptics return soon after a system vibration replaces the window.
        private const val WINDOW = 3.0
        private const val OVERLAP = 1.5
        private const val LEAD = 0.03

        /** Reads the haptics file from app/src/main/assets. */
        fun fromAsset(context: Context, player: Player, fileName: String = "share-golden.json"): HapticVideoSync {
            val json = context.assets.open(fileName).bufferedReader().use { it.readText() }
            return HapticVideoSync(context, player, json)
        }
    }
}

internal object FeelHaptics {
    class Point(val time: Double, val value: Double)

    class Event(
        val type: String,
        val start: Double,
        val duration: Double,
        val intensity: Double,
        val sharpness: Double,
        val repetitionInterval: Double,
        val repetitionCount: Int,
        val fadeIn: Double,
        val fadeOut: Double,
        val intensityCurve: List<Point>,
    )

    class Waveform(val timings: LongArray, val amplitudes: IntArray)

    private const val SLOT = 0.01
    private const val GAP_SLOTS = 3

    /** Throws [IllegalArgumentException] when the text is not a Feel haptics file that this code can read. */
    fun parse(json: String): List<Event> {
        val root = JSONObject(json)
        require(root.optString("format") == "feel-haptics") { "This file is not a Feel haptics file." }
        require(root.optInt("version", 1) <= 1) { "This haptics file is from a newer version of Feel." }
        val list = root.getJSONArray("events")
        return (0 until list.length()).map { event(list.getJSONObject(it)) }.sortedBy { it.start }
    }

    private fun event(o: JSONObject) = Event(
        type = o.getString("type"),
        start = o.optDouble("start", 0.0),
        duration = o.optDouble("duration", 0.0),
        intensity = o.optDouble("intensity", 0.8),
        sharpness = o.optDouble("sharpness", 0.5),
        repetitionInterval = o.optDouble("repetitionInterval", 0.1),
        repetitionCount = o.optInt("repetitionCount", 1),
        fadeIn = o.optDouble("fadeIn", 0.0),
        fadeOut = o.optDouble("fadeOut", 0.0),
        intensityCurve = curve(o.optJSONArray("intensityCurve")),
    )

    private fun curve(a: JSONArray?): List<Point> =
        if (a == null) emptyList() else (0 until a.length()).map {
            val p = a.getJSONObject(it)
            Point(p.optDouble("time", 0.0), p.optDouble("value", 1.0))
        }

    /**
     * Turns events into one amplitude waveform. Time 0 of the waveform is `from`. Null when the window is empty.
     * A phone motor plays one effect at a time, so overlapping events merge by the strongest value in each 10 ms slot.
     * A rumble stops briefly around a tap. Without the gaps the tap is not felt inside it.
     */
    fun waveform(events: List<Event>, from: Double, to: Double): Waveform? {
        val slots = ((to - from) / SLOT).toInt()
        if (slots <= 0) return null
        val amp = IntArray(slots)
        val tapAmp = IntArray(slots)

        fun put(target: IntArray, slot: Int, value: Int) {
            if (slot in 0 until slots && value > target[slot]) target[slot] = value
        }

        fun pulse(t: Double, intensity: Double, sharpness: Double) {
            val s = ((t - from) / SLOT).roundToInt()
            // A phone motor needs about 40 ms to spin up. Shorter pulses are not felt.
            val len = (6 - 2 * sharpness.coerceIn(0.0, 1.0)).roundToInt().coerceIn(4, 6)
            val a = level(intensity, 60)
            for (k in 0 until len) put(tapAmp, s + k, a)
        }

        for (e in events) {
            val intensity = e.intensity.coerceIn(0.0, 1.0)
            when (e.type) {
                "tap" -> if (e.start >= from && e.start < to) pulse(e.start, intensity, e.sharpness)
                "tickTrain" -> for (k in 0 until e.repetitionCount.coerceIn(1, 400)) {
                    val t = e.start + k * max(e.repetitionInterval, 0.02)
                    if (t >= from && t < to) pulse(t, intensity, e.sharpness)
                }
                "rumble" -> {
                    val dur = max(e.duration, 0.05)
                    val firstSlot = ((max(e.start, from) - from) / SLOT).roundToInt()
                    val lastSlot = ((min(e.start + dur, to) - from) / SLOT).roundToInt()
                    for (s in firstSlot until lastSlot) {
                        val t = from + s * SLOT
                        put(amp, s, level(intensity * envelope(e, t - e.start, dur), 35))
                    }
                }
            }
        }

        // Clear the rumble around each tap, then lay the taps on top.
        val gap = BooleanArray(slots)
        for (s in 0 until slots) {
            if (tapAmp[s] > 0) for (k in max(s - GAP_SLOTS, 0)..min(s + GAP_SLOTS, slots - 1)) gap[k] = true
        }
        for (s in 0 until slots) {
            if (gap[s]) amp[s] = 0
            if (tapAmp[s] > 0) amp[s] = tapAmp[s]
        }

        var end = slots
        while (end > 0 && amp[end - 1] == 0) end--
        if (end == 0) return null

        val timings = ArrayList<Long>()
        val amplitudes = ArrayList<Int>()
        var i = 0
        while (i < end) {
            var j = i
            while (j < end && amp[j] == amp[i]) j++
            timings.add(((j - i) * SLOT * 1000).roundToInt().toLong())
            amplitudes.add(amp[i])
            i = j
        }
        return Waveform(timings.toLongArray(), amplitudes.toIntArray())
    }

    /** For a motor with no amplitude control. The result alternates off, on, off, and starts with off. */
    fun onOffTimings(timings: LongArray, amplitudes: IntArray): LongArray {
        val out = ArrayList<Long>()
        out.add(0L)
        var on = false
        for (i in timings.indices) {
            val pieceOn = amplitudes[i] > 0
            if (pieceOn == on) {
                out[out.size - 1] = out.last() + timings[i]
            } else {
                out.add(timings[i])
                on = pieceOn
            }
        }
        return out.toLongArray()
    }

    /** 0...1 to motor amplitude 1...255. Weak values do not move the motor, so lift them. */
    private fun level(v: Double, floor: Int): Int =
        if (v <= 0.0) 0 else (floor + (255 - floor) * v.coerceIn(0.0, 1.0).pow(0.8)).roundToInt().coerceIn(1, 255)

    private fun envelope(e: Event, t: Double, duration: Double): Double {
        var v = interpolate(e.intensityCurve, t)
        if (e.fadeIn > 0 && t < e.fadeIn) v *= t / e.fadeIn
        if (e.fadeOut > 0 && t > duration - e.fadeOut) v *= max((duration - t) / e.fadeOut, 0.0)
        return v.coerceIn(0.0, 1.0)
    }

    private fun interpolate(points: List<Point>, t: Double): Double {
        val first = points.firstOrNull() ?: return 1.0
        val last = points.last()
        if (t <= first.time) return first.value
        if (t >= last.time) return last.value
        for (i in 1 until points.size) {
            if (t <= points[i].time) {
                val a = points[i - 1]
                val b = points[i]
                val span = b.time - a.time
                return if (span <= 0) b.value else a.value + (b.value - a.value) * (t - a.time) / span
            }
        }
        return last.value
    }
}
