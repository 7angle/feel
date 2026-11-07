// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Builds haptics from audio and video together. Port of `AutoHaptics` in FeelCore.
 * Moments found in the video are the base. Audio gives them exact times.
 * Audio hits with no matching motion stay, but they are weaker and farther apart.
 */
object AutoHaptics {
    private const val SNAP_RADIUS = 0.12
    private const val CONFIRMED_GAP = 0.2
    private const val AUDIO_ONLY_SCALE = 0.7
    private const val AUDIO_ONLY_FLOOR = 0.5

    fun generate(spectrum: AudioSpectrum, features: List<FrameFeature>, sensitivity: Double): List<HapticEvent> {
        val s = sensitivity.coerceIn(0.0, 1.0)
        val suggestions = HeuristicSuggester.suggest(features, spectrum.envelope, s)
        val audio = AudioHaptics.generate(spectrum, s)
        val audioTaps = audio.filter { it.type == "tap" }

        val out = ArrayList<HapticEvent>()
        val taps = ArrayList<HapticEvent>()

        // Explosions and impacts always stay. They move to the nearest audio hit.
        for (suggestion in suggestions) {
            if (suggestion.kind != SuggestionKind.EXPLOSION && suggestion.kind != SuggestionKind.IMPACT) continue
            val hit = audioTaps.filter { abs(it.start - suggestion.time) <= SNAP_RADIUS }
                .minByOrNull { abs(it.start - suggestion.time) }
            val delta = if (hit != null) hit.start - suggestion.time else 0.0
            for (event in suggestion.events) {
                val moved = event.copy(start = max(0.0, event.start + delta))
                when {
                    moved.type != "tap" -> out.add(moved)
                    suggestion.kind == SuggestionKind.IMPACT && hit != null ->
                        taps.add(moved.copy(intensity = max(moved.intensity, hit.intensity), sharpness = hit.sharpness))
                    else -> taps.add(moved)
                }
            }
        }

        // Audio hits that the video confirms come next, then the others. Strongest hits go first.
        val strongest = audioTaps.sortedWith(compareBy({ -it.intensity }, { it.start }))
        val z = HeuristicSuggester.zscores(DoubleArray(features.size) { features[it].motion }, 0.01)
        val confirmed = strongest.map { confirms(features, z, s, it.start) }
        strongest.forEachIndexed { i, tap ->
            if (confirmed[i] && isClear(tap.start, taps, CONFIRMED_GAP)) taps.add(tap)
        }
        val audioOnlyGap = 1 / (0.5 + s)
        strongest.forEachIndexed { i, tap ->
            if (!confirmed[i] && isClear(tap.start, taps, audioOnlyGap)) {
                taps.add(tap.copy(intensity = max(tap.intensity * AUDIO_ONLY_SCALE, AUDIO_ONLY_FLOOR)))
            }
        }
        out.addAll(taps)

        // Rumbles. The first in this order wins when two cover the same time.
        fun motionRumbles(kind: SuggestionKind) = suggestions.filter { it.kind == kind }.flatMap { it.events }
        val rumbles = motionRumbles(SuggestionKind.HIGH_ACTION) + audio.filter { it.type == "rumble" } +
            motionRumbles(SuggestionKind.CAMERA_SHAKE) + motionRumbles(SuggestionKind.FAST_MOVEMENT)
        val kept = out.filter { it.type == "rumble" }.toMutableList()
        for (rumble in rumbles) {
            if (mostlyCovered(rumble, kept)) continue
            kept.add(rumble)
            out.add(rumble)
        }
        return out.sortedBy { it.start }
    }

    private fun isClear(time: Double, taps: List<HapticEvent>, gap: Double) = taps.none { abs(it.start - time) < gap }

    private fun mostlyCovered(rumble: HapticEvent, others: List<HapticEvent>) = others.any { other ->
        min(rumble.start + rumble.duration, other.start + other.duration) - max(rumble.start, other.start) > rumble.duration / 2
    }

    /** Tells if the picture has a sudden change near a given time. */
    private fun confirms(f: List<FrameFeature>, z: DoubleArray, sensitivity: Double, time: Double): Boolean {
        if (f.size <= 6) return false
        val step = (f[f.size - 1].t - f[0].t) / (f.size - 1)
        if (step <= 0) return false
        val center = Math.round((time - f[0].t) / step).toInt()
        val lo = center - 2
        val hi = center + 2
        if (lo < 4 || hi >= f.size) return false
        val threshold = (7 - 5 * sensitivity) * 0.6
        val before = (f[lo - 4].motion + f[lo - 3].motion + f[lo - 2].motion + f[lo - 1].motion) / 4
        return (lo..hi).any { z[it] > threshold && f[it].motion > 0.03 && f[it].motion > 1.4 * before + 0.01 }
    }
}
