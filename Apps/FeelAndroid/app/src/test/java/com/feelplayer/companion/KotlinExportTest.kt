// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import com.feelplayer.haptics.FeelHaptics
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** Tests the Kotlin file that the editor exports. The fixture comes from `ExportTests.testKotlinFixtureIsCurrent`. */
class KotlinExportTest {
    private fun resource(name: String): String =
        checkNotNull(javaClass.classLoader?.getResource(name)) { "missing $name" }.readText()

    @Test
    fun exportedWaveformMatchesTheCompanionApp() {
        val text = resource("share-golden.json")
        val exported = FeelHaptics.parse(text)
        val companion = HapticShare.decode(text).events
        assertEquals(companion.size, exported.size)
        for (from in listOf(0.0, 2.0, 2.03, 8.5, 15.0)) {
            val a = FeelHaptics.waveform(exported, from, from + 10)
            val b = HapticWaveform.build(companion, from, from + 10)
            assertEquals("window $from", b == null, a == null)
            if (a != null && b != null) {
                assertArrayEquals("window $from", b.timings, a.timings)
                assertArrayEquals("window $from", b.amplitudes, a.amplitudes)
            }
        }
        assertNotNull(FeelHaptics.waveform(exported, 0.0, 10.0))
    }

    @Test
    fun onOffTimingsMergeStrengthsAndAlternate() {
        val out = FeelHaptics.onOffTimings(longArrayOf(100, 50, 30, 20, 40), intArrayOf(0, 200, 90, 0, 255))
        assertArrayEquals(longArrayOf(100, 80, 20, 40), out)
        // A waveform that starts on has an off time of zero first.
        assertArrayEquals(longArrayOf(0, 50, 10), FeelHaptics.onOffTimings(longArrayOf(50, 10), intArrayOf(120, 0)))
    }

    @Test
    fun refusesOtherFiles() {
        assertThrows(IllegalArgumentException::class.java) { FeelHaptics.parse("""{"a":1}""") }
        assertThrows(IllegalArgumentException::class.java) {
            FeelHaptics.parse("""{"format":"feel-haptics","version":99,"events":[]}""")
        }
    }
}
