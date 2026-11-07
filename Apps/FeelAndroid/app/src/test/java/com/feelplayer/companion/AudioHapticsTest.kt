// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/** Same cases as `SpectralTests` in FeelCore, plus the parts only Android has. */
class AudioHapticsTest {
    private val sr = 16000.0

    private fun sine(f: Double, amp: Float, a: Double, b: Double, s: FloatArray, rate: Double = sr) {
        for (i in (a * rate).toInt() until (b * rate).toInt()) s[i] += amp * sin(2 * PI * f * i / rate).toFloat()
    }

    private fun signal(): FloatArray {
        val s = FloatArray((10 * sr).toInt())
        sine(440.0, 0.2f, 0.0, 10.0, s)
        sine(80.0, 0.7f, 3.0, 3.15, s)
        sine(4000.0, 0.7f, 6.0, 6.05, s)
        return s
    }

    @Test
    fun bandsSeparate() {
        val sp = SpectrumAnalyzer.analyze(signal())
        assertEquals(998.0, sp.count.toDouble(), 4.0)
        assertTrue(sp.bass[305] > sp.bass[100] * 2)
        assertTrue(sp.high[602] > sp.high[100] * 2)
    }

    @Test
    fun bassHitIsSoftAndHighClickIsSharp() {
        val e = AudioHaptics.generate(SpectrumAnalyzer.analyze(signal()), 0.7).filter { it.type == "tap" }
        val thump = e.firstOrNull { abs(it.start - 3.0) < 0.2 }
        val click = e.firstOrNull { abs(it.start - 6.0) < 0.2 }
        assertNotNull(thump)
        assertNotNull(click)
        assertTrue((thump?.sharpness ?: 1.0) < (click?.sharpness ?: 0.0))
    }

    @Test
    fun longBassPassageHasOneUnbrokenRumble() {
        val s = FloatArray((45 * sr).toInt())
        sine(440.0, 0.1f, 0.0, 45.0, s)
        sine(60.0, 0.7f, 10.0, 35.0, s)
        val r = AudioHaptics.generate(SpectrumAnalyzer.analyze(s), 0.5).filter { it.type == "rumble" }
        assertEquals(1, r.size)
        assertEquals(10.0, r[0].start, 0.3)
        assertEquals(35.0, r[0].start + r[0].duration, 0.5)
    }

    @Test
    fun silenceYieldsNothing() {
        assertTrue(AudioHaptics.generate(SpectrumAnalyzer.analyze(FloatArray((5 * sr).toInt())), 0.5).isEmpty())
    }

    @Test
    fun speechRemovesBrightHitAndKeepsLoudBassHit() {
        val sp = SpectrumAnalyzer.analyze(signal()).withSpeech(listOf(2.5..7.0))
        val e = AudioHaptics.generate(sp, 0.7).filter { it.type == "tap" }
        assertNotNull(e.firstOrNull { abs(it.start - 3.0) < 0.2 })
        assertNull(e.firstOrNull { abs(it.start - 6.0) < 0.2 })
    }

    @Test
    fun speechRangesMergeAndTrim() {
        assertEquals(
            listOf(0.2..1.3, 2.2..2.8),
            SpeechRanges.merged(listOf(2.0..3.0, 0.0..1.0, 0.5..1.5, 5.0..5.3), 0.2)
                .map { (Math.round(it.start * 1e6) / 1e6)..(Math.round(it.endInclusive * 1e6) / 1e6) },
        )
    }

    @Test
    fun steadyToneGivesNoTaps() {
        val s = FloatArray((8 * sr).toInt())
        sine(440.0, 0.5f, 0.0, 8.0, s)
        assertTrue(AudioHaptics.generate(SpectrumAnalyzer.analyze(s), 0.7).none { it.type == "tap" })
    }

    private fun resample(input: FloatArray, rate: Int, chunk: Int): FloatArray {
        val out = ArrayList<Float>()
        val sink: (FloatArray, Int) -> Unit = { a, n -> for (i in 0 until n) out.add(a[i]) }
        val r = Resampler(rate)
        var pos = 0
        while (pos < input.size) {
            val n = minOf(chunk, input.size - pos)
            r.push(input.copyOfRange(pos, pos + n), n, sink)
            pos += n
        }
        r.finish(sink)
        return out.toFloatArray()
    }

    private fun rms(v: FloatArray, from: Int, to: Int): Double {
        var sum = 0.0
        for (i in from until to) sum += v[i] * v[i]
        return sqrt(sum / (to - from))
    }

    @Test
    fun resamplerKeepsLengthAndToneLevel() {
        for (rate in listOf(44100, 48000)) {
            val s = FloatArray(rate * 2)
            sine(1000.0, 0.5f, 0.0, 2.0, s, rate.toDouble())
            val out = resample(s, rate, 1771)
            assertEquals("$rate length", 32000.0, out.size.toDouble(), 2.0)
            assertEquals("$rate level", 0.5 / sqrt(2.0), rms(out, 2000, 30000), 0.01)
        }
    }

    @Test
    fun resamplerKeepsTime() {
        val rate = 48000
        val s = FloatArray(rate * 2)
        s[rate] = 1f // click at 1 s
        val out = resample(s, rate, 4096)
        val peak = out.indices.maxByOrNull { abs(out[it]) } ?: -1
        assertEquals(16000.0, peak.toDouble(), 1.0)
    }

    @Test
    fun resamplerRemovesWhatWouldFoldBack() {
        val rate = 48000
        val s = FloatArray(rate * 2)
        sine(11000.0, 0.5f, 0.0, 2.0, s, rate.toDouble()) // above the 8 kHz limit
        val out = resample(s, rate, 1024)
        assertTrue(rms(out, 2000, 30000) < 0.005)
    }

    @Test
    fun resamplerPassesMatchingRate() {
        val s = FloatArray(1000) { it / 1000f }
        val out = resample(s, 16000, 100)
        assertEquals(1000, out.size)
        assertEquals(s[500], out[500], 0f)
    }

    @Test
    fun shareRejectsOtherFiles() {
        assertThrows(HapticShare.ShareException::class.java) { HapticShare.decode("not json") }
        assertThrows(HapticShare.ShareException::class.java) { HapticShare.decode("""{"a":1}""") }
        val newer = """{"format":"feel-haptics","version":99,"events":[]}"""
        val e = assertThrows(HapticShare.ShareException::class.java) { HapticShare.decode(newer) }
        assertFalse(e.message.isNullOrEmpty())
    }

    @Test
    fun shareWithoutVideoHasUnknownMatch() {
        val doc = HapticShare.decode("""{"format":"feel-haptics","version":1,"events":[]}""")
        assertEquals(HapticShare.Match.Unknown, HapticShare.match(doc, 10.0))
    }
}
