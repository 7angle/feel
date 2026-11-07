// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public enum HapticEventType: String, Codable, CaseIterable, Sendable {
    case tap
    case rumble
    case tickTrain

    public var title: String {
        switch self {
        case .tap: "Tap"
        case .rumble: "Continuous Rumble"
        case .tickTrain: "Tick Train"
        }
    }
}

/// Point on an intensity or sharpness curve.
/// `time` is relative to event start, seconds. `value` is 0...1 multiplier.
public struct CurvePoint: Codable, Equatable, Sendable {
    public var time: TimelineTime
    public var value: Double

    public init(time: TimelineTime, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct HapticEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: HapticEventType
    /// Start on the timeline, seconds.
    public var start: TimelineTime
    /// Seconds. Taps use a small nominal width for display only.
    public var duration: TimelineTime
    public var intensity: Double
    public var sharpness: Double
    /// Tick train: seconds between ticks.
    public var repetitionInterval: TimelineTime
    /// Tick train: number of ticks.
    public var repetitionCount: Int
    public var fadeIn: TimelineTime
    public var fadeOut: TimelineTime
    public var intensityCurve: [CurvePoint]
    public var sharpnessCurve: [CurvePoint]
    public var presetID: String?
    /// The generator that made this event. nil after a user edit, so a new run replaces only untouched events.
    public var generatedBy: String?

    public init(
        id: UUID = UUID(),
        type: HapticEventType,
        start: TimelineTime,
        duration: TimelineTime = 0,
        intensity: Double = 0.8,
        sharpness: Double = 0.5,
        repetitionInterval: TimelineTime = 0.1,
        repetitionCount: Int = 1,
        fadeIn: TimelineTime = 0,
        fadeOut: TimelineTime = 0,
        intensityCurve: [CurvePoint] = [],
        sharpnessCurve: [CurvePoint] = [],
        presetID: String? = nil,
        generatedBy: String? = nil
    ) {
        self.id = id
        self.type = type
        self.start = start
        self.duration = duration
        self.intensity = intensity
        self.sharpness = sharpness
        self.repetitionInterval = repetitionInterval
        self.repetitionCount = repetitionCount
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.intensityCurve = intensityCurve
        self.sharpnessCurve = sharpnessCurve
        self.presetID = presetID
        self.generatedBy = generatedBy
    }

    /// Span used on the timeline. Tap = nominal width. Tick train = full train length.
    public var effectiveDuration: TimelineTime {
        switch type {
        case .tap: return 0.05
        case .rumble: return max(duration, 0.05)
        case .tickTrain: return max(Double(max(repetitionCount - 1, 0)) * repetitionInterval + 0.05, 0.05)
        }
    }

    public var end: TimelineTime { start + effectiveDuration }

    /// How hard this event hits at timeline time `t`, 0...1. For display, not playback.
    public func level(at t: TimelineTime) -> Double {
        let local = t - start
        guard local >= 0 else { return 0 }
        let decay = 0.12
        switch type {
        case .tap:
            return local < decay ? intensity * (1 - local / decay) : 0
        case .tickTrain:
            let gap = max(repetitionInterval, 0.02)
            guard Int(local / gap) < repetitionCount else { return 0 }
            let phase = local.truncatingRemainder(dividingBy: gap)
            let tail = min(gap, decay)
            return phase < tail ? intensity * (1 - phase / tail) : 0
        case .rumble:
            guard local <= duration else { return 0 }
            var v = intensity * Self.curveValue(intensityCurve, at: local)
            if fadeIn > 0, local < fadeIn { v *= local / fadeIn }
            if fadeOut > 0, duration - local < fadeOut { v *= (duration - local) / fadeOut }
            return v
        }
    }

    private static func curveValue(_ points: [CurvePoint], at t: TimelineTime) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        guard let i = points.firstIndex(where: { $0.time >= t }), i > 0 else { return last.value }
        let a = points[i - 1], b = points[i]
        let gap = b.time - a.time
        return gap > 0 ? a.value + (b.value - a.value) * (t - a.time) / gap : b.value
    }

    /// Clamp all values into valid ranges.
    public func normalized() -> HapticEvent {
        var e = self
        e.start = max(e.start, 0)
        e.duration = max(e.duration, 0)
        e.intensity = min(max(e.intensity, 0), 1)
        e.sharpness = min(max(e.sharpness, 0), 1)
        e.repetitionInterval = max(e.repetitionInterval, 0.02)
        e.repetitionCount = max(e.repetitionCount, 1)
        e.fadeIn = min(max(e.fadeIn, 0), e.duration)
        e.fadeOut = min(max(e.fadeOut, 0), max(e.duration - e.fadeIn, 0))
        e.intensityCurve = e.intensityCurve.map { CurvePoint(time: max($0.time, 0), value: min(max($0.value, 0), 1)) }.sorted { $0.time < $1.time }
        e.sharpnessCurve = e.sharpnessCurve.map { CurvePoint(time: max($0.time, 0), value: min(max($0.value, 0), 1)) }.sorted { $0.time < $1.time }
        return e
    }
}

public extension Array where Element == HapticEvent {
    /// Strongest event at timeline time `t`, 0...1.
    func level(at t: TimelineTime) -> Double {
        var top = 0.0
        for e in self where t >= e.start { top = Swift.max(top, e.level(at: t)) }
        return top
    }
}
