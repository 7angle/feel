// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticGraphTest {
    @Test
    fun emptyWithoutEventsOrLength() {
        assertTrue(HapticGraph.levels(emptyList(), 10.0).isEmpty())
        assertTrue(HapticGraph.levels(listOf(HapticEvent(type = "tap", start = 1.0)), 0.0).isEmpty())
    }

    @Test
    fun peaksWhereHapticsAreDense() {
        val dense = List(10) { HapticEvent(type = "tap", start = 75 + it * 0.1) }
        val levels = HapticGraph.levels(listOf(HapticEvent(type = "tap", start = 10.0)) + dense, 100.0, 100)
        assertEquals(100, levels.size)
        assertEquals(1.0, levels.max(), 1e-9)
        assertEquals(1.0, levels[75], 0.2)
        assertTrue(levels[10] < 0.3)
        assertEquals(0.0, levels[40], 1e-9)
    }

    @Test
    fun fallsToZeroAtBothEnds() {
        val levels = HapticGraph.levels(List(100) { HapticEvent(type = "tap", start = it.toDouble()) }, 100.0, 100)
        assertEquals(0.0, levels.first(), 1e-9)
        assertEquals(0.0, levels.last(), 1e-9)
        assertTrue(levels[50] > 0.5)
    }

    @Test
    fun eventPastTheEndIsIgnored() {
        assertTrue(HapticGraph.levels(listOf(HapticEvent(type = "tap", start = 20.0)), 10.0).isEmpty())
    }
}
