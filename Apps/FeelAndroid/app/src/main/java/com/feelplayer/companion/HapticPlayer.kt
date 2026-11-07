// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** Plays haptic windows on the phone motor. Main thread only. */
class HapticPlayer(context: Context) {
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
        @Suppress("DEPRECATION") (context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
    }
    private val handler = Handler(Looper.getMainLooper())
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    val supportsHaptics: Boolean get() = vibrator.hasVibrator()
    val hasAmplitudeControl: Boolean get() = vibrator.hasAmplitudeControl()

    var windowsPlayed = 0
        private set
    var lastItems = 0
        private set

    /**
     * Events in [from, to). Pattern time 0 = `from`. Starts after `delay` seconds.
     * With `continuing`, the current effect plays until the new one replaces it, so no haptic is lost at the change.
     */
    fun play(events: List<HapticEvent>, from: Double, to: Double, delay: Double, continuing: Boolean = false) {
        if (continuing) handler.removeCallbacksAndMessages(null) else stop()
        val wave = HapticWaveform.build(events, from, to) ?: return
        val effect = if (hasAmplitudeControl) {
            VibrationEffect.createWaveform(wave.timings, wave.amplitudes, -1)
        } else {
            // No amplitude control: on where the amplitude is not zero.
            VibrationEffect.createWaveform(HapticWaveform.onOffTimings(wave), -1)
        }
        lastItems = wave.timings.size
        val run = Runnable {
            @Suppress("DEPRECATION") vibrator.vibrate(effect, attributes)
            windowsPlayed++
            android.util.Log.i("Feel", "vibrate window #$windowsPlayed pieces=${wave.timings.size} total=${wave.timings.sum()}ms")
        }
        if (delay <= 0.002) run.run() else handler.postDelayed(run, (delay * 1000).toLong())
    }

    fun audition(e: HapticEvent) {
        play(listOf(e.copy(start = 0.0)), 0.0, max(e.duration, 0.0) + 0.5 + e.repetitionCount * e.repetitionInterval, 0.0)
    }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        vibrator.cancel()
    }

    private fun max(a: Double, b: Double) = if (a > b) a else b
}
