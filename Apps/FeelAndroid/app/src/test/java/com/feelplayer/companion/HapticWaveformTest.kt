// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticWaveformTest {
    /** One amplitude per 10 ms slot. */
    private fun slots(r: HapticWaveform.Result): IntArray {
        val out = ArrayList<Int>()
        for (i in r.timings.indices) repeat((r.timings[i] / 10).toInt()) { out.add(r.amplitudes[i]) }
        return out.toIntArray()
    }

    @Test
    fun tapInsideRumbleHasGapsOnBothSides() {
        val rumble = HapticEvent(type = "rumble", start = 0.0, duration = 1.0, intensity = 0.8)
        val tap = HapticEvent(type = "tap", start = 0.5, intensity = 0.7, sharpness = 0.5)
        val a = slots(HapticWaveform.build(listOf(rumble, tap), 0.0, 2.0)!!)
        val tapLevel = HapticWaveform.level(0.7)
        assertEquals(tapLevel, a[50])
        assertEquals(0, a[49])
        assertEquals(0, a[47])
        assertEquals(HapticWaveform.level(0.8, floor = 35), a[46])
        val lastPulse = (50 until a.size).last { a[it] == tapLevel }
        assertEquals(0, a[lastPulse + 1])
        assertEquals(0, a[lastPulse + 3])
        assertEquals(HapticWaveform.level(0.8, floor = 35), a[lastPulse + 4])
    }

    @Test
    fun rumbleWithoutTapsHasNoGaps() {
        val a = slots(HapticWaveform.build(listOf(HapticEvent(type = "rumble", start = 0.0, duration = 0.5)), 0.0, 1.0)!!)
        assertEquals(50, a.size)
        assertTrue(a.all { it > 0 })
    }

    @Test
    fun tapAloneIsUnchanged() {
        val a = slots(HapticWaveform.build(listOf(HapticEvent(type = "tap", start = 0.1, intensity = 1.0, sharpness = 1.0)), 0.0, 1.0)!!)
        assertEquals(0, a[9])
        assertEquals(255, a[10])
        assertEquals(255, a[13])
        assertEquals(14, a.size)
    }
}
