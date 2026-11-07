// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln1p
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Per-band loudness and change, 100 values per second. Index i covers audio from i/100 s.
 * Port of `AudioSpectrum` in FeelCore. `AudioGoldenTest` holds both ports to the same numbers.
 */
class AudioSpectrum(
    /** Band energy, log-compressed, 0..~1. 30-190 Hz, 190-2000 Hz, 2-8 kHz. */
    val bass: FloatArray,
    val mid: FloatArray,
    val high: FloatArray,
    /** Spectral flux: how much new energy appeared in the band since the last hop. */
    val fluxBass: FloatArray,
    val fluxMid: FloatArray,
    val fluxHigh: FloatArray,
    /** Seconds that hold speech. Empty when none was found or the classifier did not run. */
    val speech: List<ClosedFloatingPointRange<Double>> = emptyList(),
    /** Peak level 0..1, 100 values per second. */
    val envelope: FloatArray = FloatArray(0),
) {
    val count: Int get() = bass.size

    fun withSpeech(ranges: List<ClosedFloatingPointRange<Double>>) =
        AudioSpectrum(bass, mid, high, fluxBass, fluxMid, fluxHigh, ranges, envelope)

    fun withEnvelope(peaks: FloatArray) =
        AudioSpectrum(bass, mid, high, fluxBass, fluxMid, fluxHigh, speech, peaks)

    companion object {
        const val RATE = 100.0
    }
}

object SpeechRanges {
    /** Sorted ranges that do not overlap, with each side trimmed. Same rule as `SpeechDetector.merged` in FeelCore. */
    fun merged(ranges: List<ClosedFloatingPointRange<Double>>, trim: Double): List<ClosedFloatingPointRange<Double>> {
        val joined = ArrayList<ClosedFloatingPointRange<Double>>()
        for (r in ranges.sortedBy { it.start }) {
            val last = joined.lastOrNull()
            if (last != null && r.start <= last.endInclusive) {
                joined[joined.size - 1] = last.start..maxOf(last.endInclusive, r.endInclusive)
            } else {
                joined.add(r)
            }
        }
        return joined.mapNotNull { r ->
            val lo = r.start + trim
            val hi = r.endInclusive - trim
            if (lo < hi) lo..hi else null
        }
    }
}

/** Growing list of floats without boxing. */
private class FloatList(capacity: Int = 4096) {
    private var data = FloatArray(capacity)
    var size = 0
        private set

    fun add(v: Float) {
        if (size == data.size) data = data.copyOf(size * 2)
        data[size++] = v
    }

    fun toArray(): FloatArray = data.copyOf(size)
}

/** STFT with a 512-sample Hann window at 16 kHz, hop 160 samples (10 ms). */
class SpectrumAnalyzer {
    private val window = FloatArray(FRAME) { (HANN_NORM * (1 - cos(2 * PI * it / FRAME))).toFloat() }
    private val cosines = DoubleArray(FRAME / 2) { cos(2 * PI * it / FRAME) }
    private val sines = DoubleArray(FRAME / 2) { -sin(2 * PI * it / FRAME) }
    private val reversed = IntArray(FRAME) { Integer.reverse(it) ushr (32 - LOG2N) }
    private val re = DoubleArray(FRAME)
    private val im = DoubleArray(FRAME)
    private val logs = FloatArray(FRAME / 2)
    private val prevLog = FloatArray(FRAME / 2)
    private var havePrev = false

    private var pending = FloatArray(FRAME * 8)
    private var pendingCount = 0

    private val bass = FloatList()
    private val mid = FloatList()
    private val high = FloatList()
    private val fluxBass = FloatList()
    private val fluxMid = FloatList()
    private val fluxHigh = FloatList()

    /** Feed mono samples at 16 kHz, -1..1. */
    fun push(samples: FloatArray, count: Int = samples.size) {
        if (pendingCount + count > pending.size) pending = pending.copyOf(max(pending.size * 2, pendingCount + count))
        samples.copyInto(pending, pendingCount, 0, count)
        pendingCount += count
        var pos = 0
        while (pendingCount - pos >= FRAME) {
            process(pos)
            pos += HOP
        }
        if (pos > 0) {
            val drop = minOf(pos, pendingCount)
            pending.copyInto(pending, 0, drop, pendingCount)
            pendingCount -= drop
        }
    }

    private fun process(start: Int) {
        for (i in 0 until FRAME) {
            val j = reversed[i]
            re[j] = (pending[start + i] * window[i]).toDouble()
            im[j] = 0.0
        }
        fft()
        for (k in 1 until FRAME / 2) {
            // vDSP's real FFT doubles the true transform. Keep its scale so the log curve matches.
            val magnitude = 2 * sqrt(re[k] * re[k] + im[k] * im[k])
            logs[k] = ln1p((magnitude * 0.05).toFloat())
        }
        band(BASS_FIRST, BASS_LAST, bass, fluxBass)
        band(MID_FIRST, MID_LAST, mid, fluxMid)
        band(HIGH_FIRST, HIGH_LAST, high, fluxHigh)
        logs.copyInto(prevLog)
        havePrev = true
    }

    private fun band(first: Int, last: Int, levels: FloatList, fluxes: FloatList) {
        var sum = 0f
        var flux = 0f
        for (k in first..last) {
            sum += logs[k]
            if (havePrev) flux += max(0f, logs[k] - prevLog[k])
        }
        val c = (last - first + 1).toFloat()
        levels.add(sum / c)
        fluxes.add(flux / c)
    }

    /** In-place radix-2 transform. Input is already in bit-reversed order. */
    private fun fft() {
        var size = 2
        while (size <= FRAME) {
            val half = size / 2
            val step = FRAME / size
            var start = 0
            while (start < FRAME) {
                for (k in 0 until half) {
                    val w = k * step
                    val a = start + k
                    val b = a + half
                    val tr = re[b] * cosines[w] - im[b] * sines[w]
                    val ti = re[b] * sines[w] + im[b] * cosines[w]
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                start += size
            }
            size *= 2
        }
    }

    fun result() = AudioSpectrum(
        bass.toArray(), mid.toArray(), high.toArray(),
        fluxBass.toArray(), fluxMid.toArray(), fluxHigh.toArray(),
    )

    companion object {
        const val SAMPLE_RATE = 16_000
        const val FRAME = 512
        const val HOP = 160
        private const val LOG2N = 9
        /** What vDSP_hann_window uses with vDSP_HANN_NORM. */
        private const val HANN_NORM = 0.8165
        // Bin k = k * 31.25 Hz.
        private const val BASS_FIRST = 1
        private const val BASS_LAST = 6
        private const val MID_FIRST = 7
        private const val MID_LAST = 64
        private const val HIGH_FIRST = 65
        private const val HIGH_LAST = 255

        fun analyze(samples: FloatArray): AudioSpectrum = SpectrumAnalyzer().apply { push(samples) }.result()
    }
}

/**
 * Streaming windowed-sinc resampler. The high band reaches 8 kHz, so content above that
 * must be removed first or it folds back into the band as false hits.
 * Sample rates have a small common ratio, so a few precomputed filters cover every output position.
 */
class Resampler(private val inputRate: Int, private val outputRate: Int = SpectrumAnalyzer.SAMPLE_RATE) {
    private val divisor = gcd(inputRate, outputRate)
    /** Each output sample moves `step / phases` input samples. */
    private val step = inputRate / divisor
    private val phases = outputRate / divisor
    private val cut = minOf(1.0, outputRate.toDouble() / inputRate) * 0.94
    private val halfWidth = (ZEROS / cut).toInt() + 1
    private val filters = Array(if (inputRate == outputRate) 0 else phases) { phase ->
        val frac = phase.toDouble() / phases
        FloatArray(halfWidth * 2) { k -> coefficient(k - halfWidth + 1 - frac) }
    }

    /** Starts with silence, so the first output sample lines up with the first input sample. */
    private var buffer = FloatArray(maxOf(halfWidth * 8, 4096))
    private var count = halfWidth
    /** Stream position of buffer index 0, in input samples. Negative during the leading silence. */
    private var bufferStart = -halfWidth.toLong()
    private var emitted = 0L
    private var received = 0L
    private val output = FloatArray(1024)

    private fun coefficient(x: Double): Float {
        val u = abs(x) / halfWidth
        if (u >= 1) return 0f
        val sinc = if (x == 0.0) 1.0 else sin(PI * cut * x) / (PI * cut * x)
        // Blackman window.
        val w = 0.42 + 0.5 * cos(PI * u) + 0.08 * cos(2 * PI * u)
        return (cut * sinc * w).toFloat()
    }

    /** Calls `out` with arrays of 16 kHz samples. */
    fun push(samples: FloatArray, length: Int = samples.size, out: (FloatArray, Int) -> Unit) {
        if (inputRate == outputRate) { out(samples, length); return }
        ensureRoom(length)
        samples.copyInto(buffer, count, 0, length)
        count += length
        received += length
        drain(out, Long.MAX_VALUE)
    }

    /** End of stream. Pads with silence so the last samples come out. */
    fun finish(out: (FloatArray, Int) -> Unit) {
        if (inputRate == outputRate) return
        val pad = halfWidth + 1
        ensureRoom(pad)
        buffer.fill(0f, count, count + pad)
        count += pad
        drain(out, received * phases / step)
    }

    private fun ensureRoom(extra: Int) {
        if (count + extra > buffer.size) buffer = buffer.copyOf(maxOf(buffer.size * 2, count + extra))
    }

    private fun drain(out: (FloatArray, Int) -> Unit, limit: Long) {
        var n = 0
        while (emitted < limit) {
            val position = emitted * step
            val whole = position / phases
            val first = (whole - bufferStart).toInt() - halfWidth + 1
            if (first + halfWidth * 2 > count) break
            val filter = filters[(position % phases).toInt()]
            val data = buffer
            var sum = 0f
            for (k in filter.indices) sum += data[first + k] * filter[k]
            output[n++] = sum
            emitted++
            if (n == output.size) { out(output, n); n = 0 }
        }
        if (n > 0) out(output, n)
        // Keep only what the next output sample can still reach.
        val keepFrom = (emitted * step / phases - bufferStart).toInt() - halfWidth + 1
        if (keepFrom > 0) {
            val drop = minOf(keepFrom, count)
            buffer.copyInto(buffer, 0, drop, count)
            count -= drop
            bufferStart += drop
        }
    }

    private companion object {
        const val ZEROS = 16

        tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
    }
}
