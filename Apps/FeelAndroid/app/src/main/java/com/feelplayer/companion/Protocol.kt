// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.os.SystemClock
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/** Same clock for every timestamp. Seconds, monotonic. */
object SharedClock {
    fun now(): Double = SystemClock.elapsedRealtimeNanos() / 1e9
}

data class CurvePoint(val time: Double, val value: Double)

data class HapticEvent(
    val id: String = "",
    val type: String, // tap | rumble | tickTrain
    val start: Double,
    val duration: Double = 0.0,
    val intensity: Double = 0.8,
    val sharpness: Double = 0.5,
    val repetitionInterval: Double = 0.1,
    val repetitionCount: Int = 1,
    val fadeIn: Double = 0.0,
    val fadeOut: Double = 0.0,
    val intensityCurve: List<CurvePoint> = emptyList(),
    val sharpnessCurve: List<CurvePoint> = emptyList(),
) {
    companion object {
        fun fromJson(o: JSONObject) = HapticEvent(
            id = o.optString("id"),
            type = o.getString("type"),
            start = o.optDouble("start", 0.0),
            duration = o.optDouble("duration", 0.0),
            intensity = o.optDouble("intensity", 0.8),
            sharpness = o.optDouble("sharpness", 0.5),
            repetitionInterval = o.optDouble("repetitionInterval", 0.1),
            repetitionCount = o.optInt("repetitionCount", 1),
            fadeIn = o.optDouble("fadeIn", 0.0),
            fadeOut = o.optDouble("fadeOut", 0.0),
            intensityCurve = curve(o.optJSONArray("intensityCurve")),
            sharpnessCurve = curve(o.optJSONArray("sharpnessCurve")),
        )

        private fun curve(a: JSONArray?): List<CurvePoint> =
            if (a == null) emptyList() else (0 until a.length()).map {
                val p = a.getJSONObject(it)
                CurvePoint(p.optDouble("time", 0.0), p.optDouble("value", 1.0))
            }
    }
}

/** Messages the editor sends. Unknown ones are dropped. */
sealed interface Incoming {
    data class Hello(val name: String) : Incoming
    data class Pong(val t0: Double, val t1: Double, val t2: Double) : Incoming
    data class Pattern(val revision: Int, val events: List<HapticEvent>) : Incoming
    data class Play(val mediaTime: Double, val hostTime: Double, val advance: Double) : Incoming
    data class Pause(val mediaTime: Double) : Incoming
    data class Audition(val event: HapticEvent) : Incoming
    data class VideoOffer(val id: String, val name: String, val size: Long) : Incoming
    class VideoChunk(val id: String, val offset: Long, val data: ByteArray) : Incoming
    data class VideoEnd(val id: String) : Incoming
    data object VideoClear : Incoming
    data class Timeline(val duration: Double) : Incoming
    data object Bye : Incoming
    data object Ignored : Incoming
}

/** Newline-delimited JSON. Shapes match Swift's synthesized Codable enums. */
object Wire {
    fun decode(line: String): Incoming {
        val root = JSONObject(line)
        val key = root.keys().next()
        val body = root.getJSONObject(key)
        return when (key) {
            "hello" -> Incoming.Hello(body.getJSONObject("_0").optString("name", "Mac"))
            "pong" -> Incoming.Pong(body.getDouble("t0"), body.getDouble("t1"), body.getDouble("t2"))
            "pattern" -> {
                val a = body.getJSONArray("events")
                Incoming.Pattern(body.getInt("revision"), (0 until a.length()).map { HapticEvent.fromJson(a.getJSONObject(it)) })
            }
            "play" -> Incoming.Play(body.getDouble("mediaTime"), body.getDouble("hostTime"), body.getDouble("advance"))
            "pause" -> Incoming.Pause(body.getDouble("mediaTime"))
            "audition" -> Incoming.Audition(HapticEvent.fromJson(body.getJSONObject("_0")))
            "videoOffer" -> Incoming.VideoOffer(body.getString("id"), body.getString("name"), body.getLong("size"))
            "videoChunk" -> Incoming.VideoChunk(body.getString("id"), body.getLong("offset"), Base64.decode(body.getString("data"), Base64.DEFAULT))
            "videoEnd" -> Incoming.VideoEnd(body.getString("id"))
            "videoClear" -> Incoming.VideoClear
            "timeline" -> Incoming.Timeline(body.getDouble("duration"))
            "bye" -> Incoming.Bye
            else -> Incoming.Ignored
        }
    }

    private fun line(key: String, body: JSONObject): ByteArray =
        (JSONObject().put(key, body).toString() + "\n").toByteArray(Charsets.UTF_8)

    fun hello(name: String, supportsHaptics: Boolean) = line("hello", JSONObject().put("_0", JSONObject()
        .put("name", name).put("role", "companion").put("protocolVersion", 1).put("supportsHaptics", supportsHaptics)))

    fun ping(id: Int, t0: Double) = line("ping", JSONObject().put("id", id).put("t0", t0))

    fun status(playing: Boolean, engineReady: Boolean, rtt: Double?, message: String?) = line("status", JSONObject().put("_0", JSONObject().apply {
        put("playing", playing); put("engineReady", engineReady)
        if (rtt != null) put("rtt", rtt)
        if (message != null) put("message", message)
    }))

    fun videoReady(id: String) = line("videoReady", JSONObject().put("id", id))
    fun videoFailed(id: String, reason: String) = line("videoFailed", JSONObject().put("id", id).put("reason", reason))
    fun remotePlay() = line("remotePlay", JSONObject())
    fun remotePause() = line("remotePause", JSONObject())
    fun remoteSeek(mediaTime: Double, final: Boolean) = line("remoteSeek", JSONObject().put("mediaTime", mediaTime).put("final", final))
    fun bye() = line("bye", JSONObject())
}

/** NTP-style offset. editorTime = localTime + offset. Trusts the lowest round trip. */
class ClockSync(private val capacity: Int = 16) {
    private class Sample(val offset: Double, val rtt: Double)
    private val samples = ArrayList<Sample>()

    @Synchronized fun add(t0: Double, t1: Double, t2: Double, t3: Double) {
        val rtt = (t3 - t0) - (t2 - t1)
        if (rtt < 0) return
        samples.add(Sample(((t1 - t0) + (t2 - t3)) / 2, rtt))
        if (samples.size > capacity) samples.removeAt(0)
    }

    private fun best(): Sample? = samples.minByOrNull { it.rtt }
    @get:Synchronized val offset: Double? get() = best()?.offset
    @get:Synchronized val rtt: Double? get() = best()?.rtt
    @Synchronized fun reset() = samples.clear()
}

/** Maps "media time m plays at editor host time h" onto this device's clock. */
object PlaybackPlan {
    class Plan(val mediaStart: Double, val delay: Double)

    fun make(mediaTime: Double, editorHostTime: Double, advance: Double, clockOffset: Double, nowLocal: Double, lead: Double = 0.03): Plan {
        val startLocal = (editorHostTime - clockOffset) - advance
        if (startLocal >= nowLocal + lead) return Plan(mediaTime, startLocal - nowLocal)
        val elapsed = nowLocal + lead - startLocal
        return Plan(mediaTime + elapsed, lead)
    }

    fun position(mediaTime: Double, editorHostTime: Double, advance: Double, clockOffset: Double, nowLocal: Double): Double =
        mediaTime + (nowLocal - ((editorHostTime - clockOffset) - advance))
}

/** How hard this event hits at timeline time [t], 0..1. Same rule as `HapticEvent.level(at:)` in FeelCore. */
fun HapticEvent.level(t: Double): Double {
    val local = t - start
    if (local < 0) return 0.0
    val decay = 0.12
    return when (type) {
        "tap" -> if (local < decay) intensity * (1 - local / decay) else 0.0
        "tickTrain" -> {
            val gap = maxOf(repetitionInterval, 0.02)
            if ((local / gap).toInt() >= repetitionCount) return 0.0
            val phase = local % gap
            val tail = minOf(gap, decay)
            if (phase < tail) intensity * (1 - phase / tail) else 0.0
        }
        else -> {
            if (local > duration) return 0.0
            var v = intensity * curveValue(intensityCurve, local)
            if (fadeIn > 0 && local < fadeIn) v *= local / fadeIn
            if (fadeOut > 0 && duration - local < fadeOut) v *= (duration - local) / fadeOut
            v
        }
    }
}

private fun curveValue(points: List<CurvePoint>, t: Double): Double {
    val first = points.firstOrNull() ?: return 1.0
    val last = points.last()
    if (t <= first.time) return first.value
    if (t >= last.time) return last.value
    val i = points.indexOfFirst { it.time >= t }
    if (i <= 0) return last.value
    val a = points[i - 1]
    val b = points[i]
    val gap = b.time - a.time
    return if (gap > 0) a.value + (b.value - a.value) * (t - a.time) / gap else b.value
}
