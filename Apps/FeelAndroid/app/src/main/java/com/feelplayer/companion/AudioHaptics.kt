// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Builds haptic events from the audio spectrum. Port of `AudioHaptics` in FeelCore.
 * Bass swells become rumbles. Hits found by spectral change become taps.
 * Bass-heavy hits feel soft and heavy. Bright hits feel sharp.
 * Speech makes no rumbles and no taps, except a loud bass hit under it.
 */
object AudioHaptics {
    /** Same limit as `AHAPBuilder.maxContinuousDuration`. */
    private const val MAX_CONTINUOUS = 30.0

    private class Candidate(val i: Int, val strength: Double)
    private class Feel(val i: Int, val level: Double, val brightness: Double, val bassShare: Double)

    fun generate(sp: AudioSpectrum, sensitivity: Double): List<HapticEvent> {
        val rate = AudioSpectrum.RATE
        val n = sp.count
        if (n <= rate.toInt() || sp.mid.size != n || sp.high.size != n) return emptyList()
        val s = sensitivity.coerceIn(0.0, 1.0)
        val duration = n / rate

        val bass = smooth(norm(sp.bass, 0.995, 0.02), 2)
        val mid = smooth(norm(sp.mid, 0.995, 0.02), 2)
        val high = smooth(norm(sp.high, 0.995, 0.02), 2)
        val fb = norm(sp.fluxBass, 0.99, 0.01)
        val fm = norm(sp.fluxMid, 0.99, 0.01)
        val fh = norm(sp.fluxHigh, 0.99, 0.01)
        if (bass.none { it > 0.05 } && mid.none { it > 0.05 } && high.none { it > 0.05 }) return emptyList()

        val out = ArrayList<HapticEvent>()

        // Rumbles follow the bass. Loud is relative to the surrounding ~10 s.
        val slow = smooth(bass, (0.15 * rate).toInt())
        val local = smooth(bass, (5 * rate).toInt())
        val swell = 1.45 - 0.3 * s
        val speaking = speechMask(sp.speech, n)
        val enter = BooleanArray(n) { !speaking[it] && slow[it] > 0.3 && slow[it] > local[it] * swell }
        for (r in runs(rumbleMask(slow, enter), (0.8 * rate).toInt(), (0.3 * rate).toInt())) {
            val t0 = r.first / rate
            val dur = (r.last - r.first + 1) / rate
            val curve = ArrayList<CurvePoint>()
            var k = 0
            while (k * 0.25 <= dur) {
                val rel = k * 0.25
                curve.add(CurvePoint(rel, min(1.0, max(0.3, slow[min(n - 1, r.first + (rel * rate).toInt())]))))
                k++
            }
            out.add(HapticEvent(
                type = "rumble", start = t0, duration = dur, intensity = 0.8, sharpness = 0.2,
                fadeIn = min(0.15, dur / 4), fadeOut = min(0.25, dur / 4), intensityCurve = curve,
            ))
        }

        // Onsets: spectral change across all bands, bass weighted most.
        val flux = smooth(DoubleArray(n) { 1.0 * fb[it] + 0.6 * fm[it] + 0.9 * fh[it] }, 1)
        // Adaptive threshold: local mean over +-0.5 s, plus a margin from the global spread.
        // Quiet passages keep their hits. Busy passages do not flood.
        val around = smooth(flux, (0.5 * rate).toInt())
        var total = 0.0
        for (v in flux) total += v
        val mean = total / n
        var squares = 0.0
        for (v in flux) squares += (v - mean) * (v - mean)
        val spread = sqrt(squares / n)
        val k = 2.0 - 0.8 * s
        val delta = spread * (0.9 - 0.7 * s)
        val radius = max(1, (0.05 * rate).toInt())
        val candidates = ArrayList<Candidate>()
        for (i in radius until n - radius) {
            val f = flux[i]
            if (f <= around[i] * k + delta) continue
            var peak = true
            for (j in i - radius..i + radius) if (flux[j] > f) { peak = false; break }
            if (peak) candidates.add(Candidate(i, f))
        }
        // Spacing is the only density rule. The cap is a safety limit, not a target.
        val maxCount = max(1, (duration * (4 + 8 * s)).toInt())
        val spacing = (0.10 * rate).toInt()
        val taken = BooleanArray(n)
        val kept = ArrayList<Candidate>()
        for (c in candidates.sortedByDescending { it.strength }) {
            if (kept.size >= maxCount) break
            var clear = true
            for (j in max(0, c.i - spacing + 1)..min(n - 1, c.i + spacing - 1)) if (taken[j]) { clear = false; break }
            if (!clear) continue
            taken[c.i] = true
            kept.add(c)
        }
        val latency = 0.02 // window centre sits after the hop start

        val feels = kept.map { c ->
            val lo = max(0, c.i - 2)
            val hi = min(n - 1, c.i + 2)
            var b = 0.0; var m = 0.0; var h = 0.0
            for (j in lo..hi) { b += fb[j]; m += fm[j]; h += fh[j] }
            val sum = max(b + m + h, 1e-6)
            // Loudest band just after the hit. The energy arrives over the next frames.
            var level = 0.0
            for (j in c.i..min(n - 1, c.i + 5)) level = maxOf(level, bass[j], mid[j], high[j])
            Feel(c.i, min(level, 1.0), (h + 0.5 * m) / sum, b / sum)
        }.filter { !speaking[it.i] || (it.bassShare > 0.5 && it.level > 0.7) }

        // Spread sharpness across the clip. Loud music would otherwise put every tap at the top.
        val brightRank = ranks(DoubleArray(feels.size) { feels[it].brightness })
        feels.forEachIndexed { index, f ->
            // Loud hits feel strong and quiet hits feel weaker. Weak or dull transients
            // are not felt on a phone, so both values have a floor.
            val intensity = 0.5 + 0.5 * f.level
            var sharpness = 0.5 + 0.5 * brightRank[index]
            if (f.bassShare > 0.5) sharpness = min(sharpness, 0.6)
            out.add(HapticEvent(type = "tap", start = f.i / rate + latency, intensity = intensity, sharpness = sharpness))
        }
        return out.sortedBy { it.start }
    }

    private fun norm(v: FloatArray, pct: Double, floor: Double): DoubleArray {
        val n = v.size
        val sorted = v.sortedArray()
        val top = max(sorted[min(n - 1, (n * pct).toInt())].toDouble(), floor)
        return DoubleArray(n) { min(v[it].toDouble() / top, 1.5) }
    }

    private fun ranks(v: DoubleArray): DoubleArray {
        if (v.size <= 1) return DoubleArray(v.size) { 0.5 }
        val order = v.indices.sortedBy { v[it] }
        val r = DoubleArray(v.size)
        order.forEachIndexed { pos, idx -> r[idx] = pos.toDouble() / (v.size - 1) }
        return r
    }

    private fun speechMask(ranges: List<ClosedFloatingPointRange<Double>>, count: Int): BooleanArray {
        val mask = BooleanArray(count)
        for (r in ranges) {
            val lo = max(0, (r.start * AudioSpectrum.RATE).toInt())
            val hi = min(count - 1, (r.endInclusive * AudioSpectrum.RATE).toInt())
            for (i in lo..hi) mask[i] = true
        }
        return mask
    }

    /**
     * The swell test only starts a rumble. The local average catches up during a long passage,
     * so the rumble then holds while the level stays near its peak, up to the limit for one event.
     */
    private fun rumbleMask(slow: DoubleArray, enter: BooleanArray): BooleanArray {
        val maxLen = (MAX_CONTINUOUS * AudioSpectrum.RATE).toInt()
        val mask = BooleanArray(slow.size)
        var start = -1
        var peak = 0.0
        for (i in slow.indices) {
            if (start >= 0) {
                peak = max(peak, slow[i])
                if (slow[i] < 0.3 || slow[i] < peak * 0.6 || i - start >= maxLen) start = -1
            } else if (enter[i]) {
                start = i
                peak = slow[i]
            }
            mask[i] = start >= 0
        }
        return mask
    }

    private fun smooth(v: DoubleArray, radius: Int): DoubleArray {
        if (radius <= 0 || v.isEmpty()) return v
        val prefix = DoubleArray(v.size + 1)
        for (i in v.indices) prefix[i + 1] = prefix[i] + v[i]
        return DoubleArray(v.size) { i ->
            val lo = max(0, i - radius)
            val hi = min(v.size - 1, i + radius)
            (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1)
        }
    }

    internal fun runs(mask: BooleanArray, minLen: Int, maxGap: Int): List<IntRange> {
        val out = ArrayList<IntRange>()
        var start = -1
        var lastTrue = 0
        for (i in mask.indices) {
            if (mask[i]) {
                if (start < 0) start = i
                lastTrue = i
            } else if (start >= 0 && i - lastTrue > maxGap) {
                if (lastTrue - start + 1 >= minLen) out.add(start..lastTrue)
                start = -1
            }
        }
        if (start >= 0 && lastTrue - start + 1 >= minLen) out.add(start..lastTrue)
        return out
    }
}
