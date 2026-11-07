// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

/** Holds the Kotlin port to the numbers FeelCore wrote. See `testWriteAutoGolden` in FeelCore. */
class AutoGoldenTest {
    private val golden = JSONObject(checkNotNull(javaClass.classLoader?.getResource("auto-golden.json")).readText())

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

    private val features: List<FrameFeature> = golden.getJSONArray("features").let { a ->
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            FrameFeature(
                o.getDouble("t"), o.getDouble("luma"), o.getDouble("histDiff"), o.getDouble("motion"),
                o.getDouble("shiftX"), o.getDouble("shiftY"), o.getDouble("bright"),
            )
        }
    }
    private val envelope: FloatArray = golden.getJSONArray("audio").let { a ->
        FloatArray(a.length()) { a.getDouble(it).toFloat() }
    }

    @Test
    fun eventsMatchSwift() {
        val spectrum = SpectrumAnalyzer.analyze(signal()).withEnvelope(envelope)
        val order = compareBy<HapticEvent>({ it.start }, { it.type })
        val runs = golden.getJSONArray("runs")
        for (r in 0 until runs.length()) {
            val run = runs.getJSONObject(r)
            val sensitivity = run.getDouble("sensitivity")
            val a = run.getJSONArray("events")
            val want = (0 until a.length()).map { HapticEvent.fromJson(a.getJSONObject(it)) }.sortedWith(order)
            val got = AutoHaptics.generate(spectrum, features, sensitivity).sortedWith(order)
            val label = "s=$sensitivity"
            assertEquals("$label count", want.size, got.size)
            for (i in got.indices) {
                assertEquals("$label type $i", want[i].type, got[i].type)
                assertEquals("$label start $i", want[i].start, got[i].start, 1e-6)
                assertEquals("$label duration $i", want[i].duration, got[i].duration, 1e-6)
                assertEquals("$label intensity $i", want[i].intensity, got[i].intensity, 2e-3)
                assertEquals("$label sharpness $i", want[i].sharpness, got[i].sharpness, 1e-3)
                assertEquals("$label curve $i", want[i].intensityCurve.size, got[i].intensityCurve.size)
            }
        }
    }

    @Test
    fun frameMeasurementsFollowThePicture() {
        val w = 160
        val h = 90
        // A bright bar that moves 3 pixels to the right.
        fun bar(left: Int) = MeasuredFrame(IntArray(w * h) { if (it % w in left until left + 20) 240 else 20 }, w, h)
        val still = bar(40).feature(1.0, bar(40))
        assertEquals(0.0, still.motion, 1e-9)
        assertEquals(0.0, still.shiftX, 1e-9)
        assertEquals(20.0 / w, still.bright, 1e-9)
        val moved = bar(43).feature(1.0, bar(40))
        assertTrue(moved.motion > 0)
        assertEquals(3.0, moved.shiftX, 1e-9)
        assertEquals(0.0, moved.histDiff, 1e-9)
        val first = bar(40).feature(0.0, null)
        assertEquals(0.0, first.motion, 1e-9)
    }
}
