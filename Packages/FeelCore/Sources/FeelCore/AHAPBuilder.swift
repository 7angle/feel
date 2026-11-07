// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Builds Apple Haptic and Audio Pattern (AHAP) dictionaries from timeline events.
/// Used by export (full timeline) and live playback (windowed, time-shifted).
public enum AHAPBuilder {
    /// Core Haptics limit per parameter curve.
    public static let maxControlPoints = 16
    /// Core Haptics limit per continuous event.
    public static let maxContinuousDuration: TimelineTime = 30

    /// - Parameters:
    ///   - from: timeline time that becomes pattern time 0.
    ///   - to: exclusive end of window. nil = no limit.
    public static func pattern(
        events: [HapticEvent],
        from: TimelineTime = 0,
        to: TimelineTime? = nil,
        description: String = "Feel haptic pattern"
    ) -> [String: Any] {
        var items: [[String: Any]] = []
        let end = to ?? .infinity
        let sorted = events.map { $0.normalized() }.sorted { $0.start < $1.start }
        let shaped = sorted.filter { $0.type == .rumble && hasIntensityShape($0) }

        for e in sorted {
            switch e.type {
            case .tap:
                if e.start >= from, e.start < end {
                    items.append(transient(e.start - from, compensated(e.intensity, at: e.start, shaped), e.sharpness))
                }
            case .tickTrain:
                for k in 0..<e.repetitionCount {
                    let t = e.start + Double(k) * e.repetitionInterval
                    if t >= from, t < end { items.append(transient(t - from, compensated(e.intensity, at: t, shaped), e.sharpness)) }
                }
            case .rumble:
                items.append(contentsOf: continuous(e, from: from, end: end))
            }
        }

        return [
            "Version": 1.0,
            "Metadata": ["Project": "Feel", "Description": description],
            "Pattern": items,
        ]
    }

    /// For live playback. A parameter curve changes all events in its pattern, so a rumble fade
    /// also changes taps. Taps get one pattern. Rumbles that overlap get different patterns.
    /// Play all the results on separate players with the same start time.
    public static func patterns(events: [HapticEvent], from: TimelineTime = 0, to: TimelineTime? = nil) -> [[String: Any]] {
        var taps: [HapticEvent] = []
        var lanes: [[HapticEvent]] = []
        for e in events.map({ $0.normalized() }).sorted(by: { $0.start < $1.start }) {
            guard e.type == .rumble else { taps.append(e); continue }
            if let i = lanes.firstIndex(where: { ($0.last?.end ?? 0) <= e.start }) {
                lanes[i].append(e)
            } else {
                lanes.append([e])
            }
        }
        return ([taps] + lanes)
            .map { pattern(events: $0, from: from, to: to) }
            .filter { !(($0["Pattern"] as? [[String: Any]])?.isEmpty ?? true) }
    }

    public static func data(events: [HapticEvent], from: TimelineTime = 0, to: TimelineTime? = nil, description: String = "Feel haptic pattern") throws -> Data {
        let dict = pattern(events: events, from: from, to: to, description: description)
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Items

    private static func r(_ v: Double) -> Double { (v * 1_000_000).rounded() / 1_000_000 }

    private static func params(_ i: Double, _ s: Double) -> [[String: Any]] {
        [["ParameterID": "HapticIntensity", "ParameterValue": r(i)],
         ["ParameterID": "HapticSharpness", "ParameterValue": r(s)]]
    }

    private static func transient(_ time: TimelineTime, _ i: Double, _ s: Double) -> [String: Any] {
        ["Event": ["Time": r(time), "EventType": "HapticTransient", "EventParameters": params(i, s)] as [String: Any]]
    }

    private static func continuous(_ e: HapticEvent, from: TimelineTime, end: TimelineTime) -> [[String: Any]] {
        let s0 = max(e.start, from)
        let s1 = min(e.start + e.duration, end)
        guard s1 - s0 > 0.001 else { return [] }
        var out: [[String: Any]] = []
        var cs = s0
        while cs < s1 - 0.001 {
            let ce = min(cs + maxContinuousDuration, s1)
            out.append(["Event": [
                "Time": r(cs - from), "EventType": "HapticContinuous", "EventDuration": r(ce - cs),
                "EventParameters": params(e.intensity, e.sharpness),
            ] as [String: Any]])
            let rel0 = cs - e.start, rel1 = ce - e.start
            if hasIntensityShape(e) {
                out.append(contentsOf: curves("HapticIntensityControl", start: cs - from, rel0, rel1, breakpoints(e)) { envelope(e, at: $0) })
            }
            if !e.sharpnessCurve.isEmpty {
                let times = e.sharpnessCurve.map(\.time)
                out.append(contentsOf: curves("HapticSharpnessControl", start: cs - from, rel0, rel1, times) {
                    // Control is additive. Map multiplier curve to offset so result = sharpness * v.
                    e.sharpness * (interp(e.sharpnessCurve, $0, default: 1) - 1)
                })
            }
            cs = ce
        }
        // A control keeps changing the pattern after this rumble. Put it back to neutral.
        let rel = s1 - e.start
        if hasIntensityShape(e) { out.append(reset("HapticIntensityControl", at: s1 - from, from: envelope(e, at: rel), to: 1)) }
        if !e.sharpnessCurve.isEmpty {
            out.append(reset("HapticSharpnessControl", at: s1 - from, from: e.sharpness * (interp(e.sharpnessCurve, rel, default: 1) - 1), to: 0))
        }
        return out
    }

    private static func reset(_ id: String, at time: TimelineTime, from a: Double, to b: Double) -> [String: Any] {
        ["ParameterCurve": [
            "ParameterID": id, "Time": r(time),
            "ParameterCurveControlPoints": [
                ["Time": 0.0, "ParameterValue": r(a)] as [String: Any],
                ["Time": 0.01, "ParameterValue": r(b)] as [String: Any],
            ],
        ] as [String: Any]]
    }

    /// In a single pattern, a rumble curve scales the taps under it. Undo that as far as the range allows.
    private static func compensated(_ intensity: Double, at t: TimelineTime, _ shaped: [HapticEvent]) -> Double {
        guard let e = shaped.last(where: { $0.start <= t && t < $0.end }) else { return intensity }
        let control = envelope(e, at: t - e.start)
        return control > 0.01 ? min(intensity / control, 1) : intensity
    }

    private static func hasIntensityShape(_ e: HapticEvent) -> Bool {
        e.fadeIn > 0 || e.fadeOut > 0 || !e.intensityCurve.isEmpty
    }

    private static func breakpoints(_ e: HapticEvent) -> [TimelineTime] {
        var t: [TimelineTime] = [0, e.duration]
        if e.fadeIn > 0 { t.append(e.fadeIn) }
        if e.fadeOut > 0 { t.append(e.duration - e.fadeOut) }
        t.append(contentsOf: e.intensityCurve.map(\.time))
        return t
    }

    /// Curves over event-relative window [rel0, rel1]. One curve holds max 16 points, so a long
    /// shape becomes a chain. Each curve starts on the last point of the previous one.
    private static func curves(
        _ id: String, start: TimelineTime, _ rel0: TimelineTime, _ rel1: TimelineTime,
        _ breaks: [TimelineTime], value: (TimelineTime) -> Double
    ) -> [[String: Any]] {
        var times = Set(breaks.filter { $0 > rel0 && $0 < rel1 })
        times.insert(rel0)
        times.insert(rel1)
        let sorted = times.sorted()
        var out: [[String: Any]] = []
        var lo = 0
        repeat {
            let hi = min(lo + maxControlPoints - 1, sorted.count - 1)
            let t0 = sorted[lo]
            let points = sorted[lo...hi].map { ["Time": r($0 - t0), "ParameterValue": r(value($0))] as [String: Any] }
            out.append(["ParameterCurve": [
                "ParameterID": id, "Time": r(start + t0 - rel0), "ParameterCurveControlPoints": points,
            ] as [String: Any]])
            lo = hi
        } while lo < sorted.count - 1
        return out
    }

    // MARK: Math

    static func interp(_ pts: [CurvePoint], _ t: TimelineTime, default d: Double) -> Double {
        guard let first = pts.first, let last = pts.last else { return d }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        for i in 1..<pts.count where t <= pts[i].time {
            let a = pts[i - 1], b = pts[i]
            let span = b.time - a.time
            return span <= 0 ? b.value : a.value + (b.value - a.value) * (t - a.time) / span
        }
        return last.value
    }

    /// Intensity multiplier at event-relative time `t`: curve * fades.
    static func envelope(_ e: HapticEvent, at t: TimelineTime) -> Double {
        var v = interp(e.intensityCurve, t, default: 1)
        if e.fadeIn > 0, t < e.fadeIn { v *= t / e.fadeIn }
        if e.fadeOut > 0, t > e.duration - e.fadeOut { v *= max((e.duration - t) / e.fadeOut, 0) }
        return min(max(v, 0), 1)
    }
}
