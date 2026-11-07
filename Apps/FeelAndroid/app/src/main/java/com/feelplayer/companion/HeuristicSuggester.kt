// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

enum class SuggestionKind { IMPACT, EXPLOSION, FAST_MOVEMENT, CAMERA_SHAKE, HIGH_ACTION }

class HapticSuggestion(val kind: SuggestionKind, val time: Double, val events: List<HapticEvent>)

/**
 * Rule-based moments from video and audio. Port of `HeuristicSuggester` in FeelCore.
 * It has no scene cuts: `AutoHaptics` does not use them. `AutoGoldenTest` holds both ports to the same numbers.
 */
object HeuristicSuggester {
    private const val AUDIO_RATE = 100.0

    fun suggest(f: List<FrameFeature>, audio: FloatArray, sensitivity: Double): List<HapticSuggestion> {
        val n = f.size
        if (n <= 6) return emptyList()
        val s = sensitivity.coerceIn(0.0, 1.0)
        val k = 7.0 - 5.0 * s
        val dt = (f[n - 1].t - f[0].t) / (n - 1)
        if (dt <= 0) return emptyList()

        val motion = DoubleArray(n) { f[it].motion }
        val mz = zscores(motion, 0.01)
        val hasAudio = audio.any { it > 0.02f }
        val ae = DoubleArray(n) { audioPeak(audio, f[it].t, dt / 2) }
        val az = zscores(ae, 0.02)
        fun onset(i: Int): Boolean {
            if (!hasAudio || i < 4) return false
            val base = (ae[i - 4] + ae[i - 3] + ae[i - 2] + ae[i - 1]) / 4
            return az[i] > k * 0.8 && ae[i] - base > 0.15
        }
        fun audioNear(i: Int, r: Int) = (max(0, i - r)..min(n - 1, i + r)).any { onset(it) }

        val cutThreshold = 0.55 - 0.3 * s
        val isCut = BooleanArray(n) { it >= 1 && f[it].histDiff > cutThreshold }
        fun cutNear(i: Int) = (max(0, i - 1)..min(n - 1, i + 1)).any { isCut[it] }

        val out = ArrayList<HapticSuggestion>()

        // Explosions: bright flash plus motion or audio burst.
        val explosionTimes = ArrayList<Double>()
        for (i in 2 until n) {
            val jump = f[i].luma - f[i - 2].luma
            if (jump <= 0.12 || f[i].bright <= 0.12 || (isCut[i] && !audioNear(i, 3))) continue
            if (mz[i] <= k * 0.6 && !audioNear(i, 3)) continue
            val last = explosionTimes.lastOrNull()
            if (last != null && f[i].t - last <= 1.0) continue
            explosionTimes.add(f[i].t)
            out.add(HapticSuggestion(SuggestionKind.EXPLOSION, f[i].t, explosion(f[i].t)))
        }

        // Impacts: motion spike plus audio onset, or a very large spike when there is no audio.
        val impactTimes = ArrayList<Double>()
        for (i in 4 until n - 3) {
            if (mz[i] <= k || motion[i] <= 0.04 || cutNear(i)) continue
            // A jump, not a plateau of sustained motion.
            val before = (motion[i - 4] + motion[i - 3] + motion[i - 2] + motion[i - 1]) / 4
            if (motion[i] <= 1.8 * before + 0.02) continue
            if (!(i - 2..i + 2).all { mz[it] <= mz[i] }) continue
            val confirmed = if (hasAudio) audioNear(i, 3) else mz[i] > k * 1.3 && motion[i + 3] < 0.6 * motion[i]
            if (!confirmed) continue
            if (explosionTimes.any { abs(it - f[i].t) < 0.5 }) continue
            val last = impactTimes.lastOrNull()
            if (last != null && f[i].t - last <= 0.25) continue
            val strength = min(1.0, max(0.3, mz[i] / (k * 2)))
            impactTimes.add(f[i].t)
            out.add(HapticSuggestion(SuggestionKind.IMPACT, f[i].t, listOf(
                HapticEvent(type = "tap", start = f[i].t, intensity = 0.5 + 0.5 * strength, sharpness = 0.8),
            )))
        }

        // Sustained motion. High action also needs loud audio.
        val moving = BooleanArray(n) { mz[it] > k * 0.5 && motion[it] > 0.03 && !cutNear(it) }
        val loud = BooleanArray(n) { moving[it] && hasAudio && az[it] > k * 0.5 }
        val actionRuns = AudioHaptics.runs(loud, (1.0 / dt).toInt(), (0.3 / dt).toInt())
        for (r in actionRuns) {
            val t0 = f[r.first].t
            val dur = min(f[r.last].t - t0, 12.0)
            val curve = ArrayList<CurvePoint>()
            var c = 0
            while (c * 0.5 <= dur) {
                val rel = c * 0.5
                val i = min(n - 1, max(0, ((t0 + rel - f[0].t) / dt).toInt()))
                curve.add(CurvePoint(rel, min(1.0, max(0.35, 0.35 + ae[i]))))
                c++
            }
            out.add(HapticSuggestion(SuggestionKind.HIGH_ACTION, t0, listOf(HapticEvent(
                type = "rumble", start = t0, duration = dur, intensity = 0.7, sharpness = 0.3,
                fadeIn = 0.2, fadeOut = 0.3, intensityCurve = curve,
            ))))
        }
        for (r in AudioHaptics.runs(moving, (0.6 / dt).toInt(), (0.25 / dt).toInt())) {
            val t0 = f[r.first].t
            if (actionRuns.any { it.first <= r.last && r.first <= it.last }) continue
            val dur = min(f[r.last].t - t0, 8.0)
            var sumZ = 0.0
            for (i in r) sumZ += mz[i]
            val strength = min(1.0, sumZ / (r.last - r.first + 1) / (k * 2))
            out.add(HapticSuggestion(SuggestionKind.FAST_MOVEMENT, t0, listOf(HapticEvent(
                type = "rumble", start = t0, duration = dur, intensity = 0.3 + 0.4 * min(1.0, strength * 1.5),
                sharpness = 0.4, fadeIn = 0.15, fadeOut = 0.25,
            ))))
        }

        // Camera shake: shift direction keeps reversing.
        val win = max((0.6 / dt).toInt(), 3)
        val shaking = BooleanArray(n) { i ->
            val lo = max(0, i - win / 2)
            val hi = min(n - 1, i + win / 2)
            var flips = 0
            var mag = 0.0
            var prev: Double? = null
            for (j in lo..hi) {
                val x = if (abs(f[j].shiftX) >= abs(f[j].shiftY)) f[j].shiftX else f[j].shiftY
                mag += sqrt(f[j].shiftX * f[j].shiftX + f[j].shiftY * f[j].shiftY)
                if (abs(x) >= 1) {
                    val p = prev
                    if (p != null && p * x < 0) flips++
                    prev = x
                }
            }
            flips >= 3 && mag / (hi - lo + 1) >= 1 && !cutNear(i)
        }
        for (r in AudioHaptics.runs(shaking, (0.5 / dt).toInt(), (0.2 / dt).toInt())) {
            val t0 = f[r.first].t
            out.add(HapticSuggestion(SuggestionKind.CAMERA_SHAKE, t0, listOf(HapticEvent(
                type = "rumble", start = t0, duration = min(f[r.last].t - t0, 8.0), intensity = 0.5,
                sharpness = 0.25, fadeIn = 0.1, fadeOut = 0.2,
            ))))
        }

        return out.sortedBy { it.time }
    }

    /** Same as the "explosion" preset in FeelCore. */
    private fun explosion(t: Double) = listOf(
        HapticEvent(type = "tap", start = t, intensity = 1.0, sharpness = 0.9),
        HapticEvent(
            type = "rumble", start = t + 0.02, duration = 1.0, intensity = 1.0, sharpness = 0.2, fadeOut = 0.9,
            intensityCurve = listOf(CurvePoint(0.0, 1.0), CurvePoint(0.3, 0.6), CurvePoint(1.0, 0.0)),
        ),
    )

    /** Robust z-score: (x - median) / (1.4826 * MAD). `floor` avoids blowing up on static content. */
    internal fun zscores(v: DoubleArray, floor: Double): DoubleArray {
        val med = median(v)
        val mad = median(DoubleArray(v.size) { abs(v[it] - med) })
        val scale = max(1.4826 * mad, floor)
        return DoubleArray(v.size) { (v[it] - med) / scale }
    }

    private fun median(v: DoubleArray): Double {
        if (v.isEmpty()) return 0.0
        val s = v.sortedArray()
        return if (s.size % 2 == 1) s[s.size / 2] else (s[s.size / 2 - 1] + s[s.size / 2]) / 2
    }

    private fun audioPeak(audio: FloatArray, t: Double, radius: Double): Double {
        if (audio.isEmpty()) return 0.0
        val lo = max(0, ((t - radius) * AUDIO_RATE).toInt())
        val hi = min(audio.size - 1, ((t + radius) * AUDIO_RATE).toInt())
        var peak = 0f
        for (i in lo..hi) peak = max(peak, audio[i])
        return peak.toDouble()
    }
}
