// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

/** Holds the Kotlin port to the numbers FeelCore wrote. See `GoldenTests.swift` in FeelCore. */
class AudioGoldenTest {
    private fun resource(name: String): String =
        checkNotNull(javaClass.classLoader?.getResource(name)) { "missing $name" }.readText()

    /** Same signal as `GoldenTests.signal()` in FeelCore. */
    private fun signal(): FloatArray {
        val sr = 16000.0
        val s = FloatArray((30 * sr).toInt())
        var x = 12345
        for (i in s.indices) {
            x = x * 1_664_525 + 1_013_904_223
            s[i] = (((x ushr 16) and 0x7fff).toFloat() / 16384 - 1) * 0.02f
        }
        fun sine(f: Double, amp: Float, a: Double, b: Double) {
            for (i in (a * sr).toInt() until (b * sr).toInt()) s[i] += amp * sin(2 * PI * f * i / sr).toFloat()
        }
        sine(440.0, 0.1f, 0.0, 30.0)
        var t = 1.0
        while (t < 29) { sine(70.0, 0.6f, t, t + 0.1); t += 1 }
        t = 2.0
        while (t < 29) { sine(4000.0, 0.5f, t, t + 0.03); t += 1.37 }
        sine(60.0, 0.7f, 15.0, 22.0)
        return s
    }

    private val golden = JSONObject(resource("audio-golden.json"))
    private val spectrum = SpectrumAnalyzer.analyze(signal())

    private fun compareBand(name: String, actual: FloatArray, bands: JSONObject) {
        val want: JSONArray = bands.getJSONArray(name)
        val step = bands.getInt("stride")
        for (i in 0 until want.length()) {
            assertEquals("$name[${i * step}]", want.getDouble(i), actual[i * step].toDouble(), 2e-4)
        }
    }

    @Test
    fun spectrumMatchesSwift() {
        val bands = golden.getJSONObject("bands")
        assertEquals(bands.getInt("count"), spectrum.count)
        compareBand("bass", spectrum.bass, bands)
        compareBand("mid", spectrum.mid, bands)
        compareBand("high", spectrum.high, bands)
        compareBand("fluxBass", spectrum.fluxBass, bands)
        compareBand("fluxMid", spectrum.fluxMid, bands)
        compareBand("fluxHigh", spectrum.fluxHigh, bands)
    }

    @Test
    fun eventsMatchSwift() {
        val runs = golden.getJSONArray("runs")
        for (r in 0 until runs.length()) {
            val run = runs.getJSONObject(r)
            val speech = run.getJSONArray("speech")
            val ranges = (0 until speech.length()).map {
                val p = speech.getJSONArray(it)
                p.getDouble(0)..p.getDouble(1)
            }
            val sensitivity = run.getDouble("sensitivity")
            val got = AudioHaptics.generate(spectrum.withSpeech(ranges), sensitivity)
            val want = run.getJSONArray("events")
            val label = "s=$sensitivity speech=${ranges.size}"
            assertEquals("$label count", want.length(), got.size)
            for (i in got.indices) {
                val w = HapticEvent.fromJson(want.getJSONObject(i))
                val g = got[i]
                assertEquals("$label type $i", w.type, g.type)
                assertEquals("$label start $i", w.start, g.start, 1e-6)
                assertEquals("$label duration $i", w.duration, g.duration, 1e-6)
                assertEquals("$label intensity $i", w.intensity, g.intensity, 2e-3)
                assertEquals("$label sharpness $i", w.sharpness, g.sharpness, 1e-3)
                assertEquals("$label curve $i", w.intensityCurve.size, g.intensityCurve.size)
            }
        }
    }

    @Test
    fun readsSwiftExport() {
        val doc = HapticShare.decode(resource("share-golden.json"))
        assertEquals(6, doc.events.size)
        assertEquals(20.0, doc.videoDuration ?: 0.0, 1e-9)
        assertEquals(doc.events.sortedBy { it.start }, doc.events)
        assertEquals(HapticShare.Match.Same, HapticShare.match(doc, 20.2))
        assertEquals(HapticShare.Match.LengthDiffers(20.0, 31.0), HapticShare.match(doc, 31.0))
    }
}
