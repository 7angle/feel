// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Turns events into one amplitude waveform. A phone motor plays one effect at a time,
 * so overlapping events merge by taking the strongest value in each 10 ms slot.
 * A rumble stops briefly around a tap. Without the gaps the tap is not felt inside it.
 */
object HapticWaveform {
    const val SLOT = 0.01
    private const val GAP_SLOTS = 3

    class Result(val timings: LongArray, val amplitudes: IntArray)

    /** Pattern time 0 = `from`. null when the window holds nothing. */
    fun build(events: List<HapticEvent>, from: Double, to: Double): Result? {
        val slots = ((to - from) / SLOT).toInt()
        if (slots <= 0) return null
        val amp = IntArray(slots)
        val tapAmp = IntArray(slots)

        fun put(target: IntArray, slot: Int, value: Int) {
            if (slot in 0 until slots && value > target[slot]) target[slot] = value
        }

        fun pulse(t: Double, intensity: Double, sharpness: Double) {
            val s = ((t - from) / SLOT).roundToInt()
            // Sharp = short and crisp. Soft = longer and rounder.
            // A phone motor needs about 40 ms to spin up. Shorter pulses are not felt.
            val len = (6 - 2 * sharpness.coerceIn(0.0, 1.0)).roundToInt().coerceIn(4, 6)
            val a = level(intensity)
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
                    val first = max(e.start, from)
                    val last = min(e.start + dur, to)
                    // Integer slots. Adding SLOT to a time collects error and leaves holes in the rumble.
                    val firstSlot = ((first - from) / SLOT).roundToInt()
                    val lastSlot = ((last - from) / SLOT).roundToInt()
                    for (s in firstSlot until lastSlot) {
                        val t = from + s * SLOT
                        put(amp, s, level(intensity * envelope(e, t - e.start, dur), floor = 35))
                    }
                }
            }
        }

        // Clear the rumble around each tap, then lay the taps on top.
        val gap = BooleanArray(slots)
        for (s in 0 until slots) {
            if (tapAmp[s] > 0) for (k in maxOf(s - GAP_SLOTS, 0)..minOf(s + GAP_SLOTS, slots - 1)) gap[k] = true
        }
        for (s in 0 until slots) {
            if (gap[s]) amp[s] = 0
            if (tapAmp[s] > 0) amp[s] = tapAmp[s]
        }

        var end = slots
        while (end > 0 && amp[end - 1] == 0) end--
        if (end == 0) return null

        val timings = ArrayList<Long>()
        val amps = ArrayList<Int>()
        var i = 0
        while (i < end) {
            var j = i
            while (j < end && amp[j] == amp[i]) j++
            timings.add(((j - i) * SLOT * 1000).roundToInt().toLong())
            amps.add(amp[i])
            i = j
        }
        return Result(timings.toLongArray(), amps.toIntArray())
    }

    /** For a motor with no amplitude control. The result alternates off, on, off, and starts with off. */
    fun onOffTimings(wave: Result): LongArray {
        val out = ArrayList<Long>()
        out.add(0L)
        var on = false
        for (i in wave.timings.indices) {
            val pieceOn = wave.amplitudes[i] > 0
            if (pieceOn == on) {
                out[out.size - 1] = out.last() + wave.timings[i]
            } else {
                out.add(wave.timings[i])
                on = pieceOn
            }
        }
        return out.toLongArray()
    }

    /** 0...1 to motor amplitude 1...255. Weak values do not move the motor, so lift them. */
    fun level(v: Double, floor: Int = 60): Int =
        if (v <= 0.0) 0 else (floor + (255 - floor) * v.coerceIn(0.0, 1.0).pow(0.8)).roundToInt().coerceIn(1, 255)

    fun interp(pts: List<CurvePoint>, t: Double, default: Double): Double {
        val first = pts.firstOrNull() ?: return default
        val last = pts.last()
        if (t <= first.time) return first.value
        if (t >= last.time) return last.value
        for (i in 1 until pts.size) {
            if (t <= pts[i].time) {
                val a = pts[i - 1]; val b = pts[i]
                val span = b.time - a.time
                return if (span <= 0) b.value else a.value + (b.value - a.value) * (t - a.time) / span
            }
        }
        return last.value
    }

    fun envelope(e: HapticEvent, t: Double, duration: Double): Double {
        var v = interp(e.intensityCurve, t, 1.0)
        if (e.fadeIn > 0 && t < e.fadeIn) v *= t / e.fadeIn
        if (e.fadeOut > 0 && t > duration - e.fadeOut) v *= max((duration - t) / e.fadeOut, 0.0)
        return v.coerceIn(0.0, 1.0)
    }
}
