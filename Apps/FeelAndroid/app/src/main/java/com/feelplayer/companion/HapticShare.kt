// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import org.json.JSONException
import org.json.JSONObject
import kotlin.math.abs

/** Reads haptics files made by the editor (JSON export). Port of `HapticShare` in FeelCore. Holds no video data. */
object HapticShare {
    private const val SUPPORTED_VERSION = 1

    class ShareException(message: String) : Exception(message)

    class Document(val events: List<HapticEvent>, val videoDuration: Double?)

    sealed interface Match {
        data object Same : Match
        data class LengthDiffers(val expected: Double, val actual: Double) : Match
        data object Unknown : Match
    }

    /** Throws [ShareException] with a message for the user. */
    fun decode(text: String): Document {
        val root = try { JSONObject(text) } catch (_: JSONException) { throw ShareException("This file is not a Feel haptics file.") }
        if (root.optString("format") != "feel-haptics") throw ShareException("This file is not a Feel haptics file.")
        if (root.optInt("version", 1) > SUPPORTED_VERSION) throw ShareException("This haptics file is from a newer version of Feel.")
        val list = root.optJSONArray("events") ?: throw ShareException("This file is not a Feel haptics file.")
        val events = try {
            (0 until list.length()).map { HapticEvent.fromJson(list.getJSONObject(it)) }.sortedBy { it.start }
        } catch (_: JSONException) {
            throw ShareException("This haptics file is damaged.")
        }
        val duration = root.optJSONObject("video")?.optDouble("duration", Double.NaN)?.takeUnless { it.isNaN() }
        return Document(events, duration)
    }

    fun match(doc: Document, videoDuration: Double, tolerance: Double = 0.5): Match {
        val expected = doc.videoDuration ?: return Match.Unknown
        return if (abs(expected - videoDuration) <= tolerance) Match.Same else Match.LengthDiffers(expected, videoDuration)
    }
}
