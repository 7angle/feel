// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.abs

/** Per-sample measurements from video. Port of `FrameFeature` in FeelCore. */
data class FrameFeature(
    val t: Double,
    /** Mean luma 0..1. */
    val luma: Double = 0.3,
    /** Histogram distance to the previous sample 0..1. Spikes on hard cuts. */
    val histDiff: Double = 0.0,
    /** Mean absolute luma change to the previous sample 0..1. */
    val motion: Double = 0.0,
    /** Estimated global shift in analysis pixels. */
    val shiftX: Double = 0.0,
    val shiftY: Double = 0.0,
    /** Fraction of near-white pixels 0..1. */
    val bright: Double = 0.0,
)

/** One small frame, luma 0..255 row by row. Same measurements as `FrameFeatureExtractor` in FeelCore. */
class MeasuredFrame(val luma: IntArray, width: Int, height: Int) {
    val hist = DoubleArray(16)
    val cols = DoubleArray(width)
    val rows = DoubleArray(height)
    val mean: Double
    val bright: Double

    init {
        var sum = 0.0
        var white = 0
        for (y in 0 until height) {
            for (x in 0 until width) {
                val l = luma[y * width + x]
                hist[l shr 4] += 1.0
                cols[x] += l.toDouble()
                rows[y] += l.toDouble()
                sum += l
                if (l > 230) white++
            }
        }
        val n = (width * height).toDouble()
        for (i in hist.indices) hist[i] /= n
        for (i in cols.indices) cols[i] /= height
        for (i in rows.indices) rows[i] /= width
        mean = sum / n / 255
        bright = white / n
    }

    fun feature(t: Double, previous: MeasuredFrame?): FrameFeature {
        val p = previous ?: return FrameFeature(t = t, luma = mean, bright = bright)
        var diff = 0.0
        for (i in luma.indices) diff += abs(luma[i] - p.luma[i])
        var histDistance = 0.0
        for (i in hist.indices) histDistance += abs(hist[i] - p.hist[i])
        return FrameFeature(
            t = t, luma = mean, histDiff = 0.5 * histDistance, motion = diff / luma.size / 255,
            shiftX = shift(cols, p.cols), shiftY = shift(rows, p.rows), bright = bright,
        )
    }

    /** Best 1-D shift in pixels between two projections, by sum of absolute differences. */
    private fun shift(a: DoubleArray, b: DoubleArray, maxLag: Int = 8): Double {
        var best = 0
        var bestCost = Double.POSITIVE_INFINITY
        for (lag in -maxLag..maxLag) {
            var cost = 0.0
            var n = 0
            for (i in maxOf(0, lag) until minOf(a.size, a.size + lag)) {
                cost += abs(a[i] - b[i - lag])
                n++
            }
            cost /= maxOf(n, 1)
            if (cost < bestCost - 1e-9) {
                bestCost = cost
                best = lag
            }
        }
        return best.toDouble()
    }
}
