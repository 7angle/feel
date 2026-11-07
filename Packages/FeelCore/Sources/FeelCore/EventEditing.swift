// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Pure editing helpers. UI-free, unit tested.
public enum EventEditing {
    public static func snap(_ t: TimelineTime, grid: TimelineTime?) -> TimelineTime {
        guard let grid, grid > 0 else { return t }
        return (t / grid).rounded() * grid
    }

    public static func defaultEvent(_ type: HapticEventType, at start: TimelineTime) -> HapticEvent {
        switch type {
        case .tap:
            return HapticEvent(type: .tap, start: start, intensity: 0.8, sharpness: 0.5)
        case .rumble:
            return HapticEvent(type: .rumble, start: start, duration: 0.5, intensity: 0.7, sharpness: 0.3)
        case .tickTrain:
            return HapticEvent(type: .tickTrain, start: start, intensity: 0.7, sharpness: 0.7, repetitionInterval: 0.1, repetitionCount: 8)
        }
    }

    /// Move events by `delta` from their `origins`. Keeps group inside [0, duration] (duration 0 = unbounded).
    /// `anchor` snaps to grid.
    public static func move(
        _ events: inout [HapticEvent],
        origins: [UUID: TimelineTime],
        delta: TimelineTime,
        anchor: UUID?,
        grid: TimelineTime?,
        duration: TimelineTime
    ) {
        guard !origins.isEmpty else { return }
        var d = delta
        if let anchor, let a = origins[anchor] { d = snap(a + d, grid: grid) - a }
        let minStart = origins.values.min() ?? 0
        d = max(d, -minStart)
        if duration > 0 {
            let maxEnd = events.filter { origins[$0.id] != nil }.map { (origins[$0.id] ?? 0) + $0.effectiveDuration }.max() ?? 0
            if maxEnd + d > duration { d = max(duration - maxEnd, -minStart) }
        }
        for i in events.indices {
            if let o = origins[events[i].id] {
                events[i].start = max(o + d, 0)
                events[i].generatedBy = nil
            }
        }
    }

    public enum ResizeEdge: Sendable { case start, end }

    /// Drag an edge of a rumble, or the end of a tick train, to time `t`. Other types unchanged.
    public static func resized(_ e: HapticEvent, edge: ResizeEdge, to t: TimelineTime, grid: TimelineTime?, limit: TimelineTime) -> HapticEvent {
        var n = e
        n.generatedBy = nil
        let snapped = snap(t, grid: grid)
        switch (e.type, edge) {
        case (.rumble, .end):
            let end = limit > 0 ? min(snapped, limit) : snapped
            n.duration = max(end - e.start, 0.05)
        case (.rumble, .start):
            let end = e.start + e.duration
            let s = min(max(snapped, 0), end - 0.05)
            let shift = e.start - s
            n.start = s
            n.duration = end - s
            n.intensityCurve = e.intensityCurve.map { CurvePoint(time: $0.time + shift, value: $0.value) }
            n.sharpnessCurve = e.sharpnessCurve.map { CurvePoint(time: $0.time + shift, value: $0.value) }
        case (.tickTrain, .end):
            let end = limit > 0 ? min(snapped, limit) : snapped
            let count = Int(((end - e.start - 0.05) / e.repetitionInterval).rounded()) + 1
            n.repetitionCount = min(max(count, 1), 200)
        default:
            break
        }
        return n.normalized()
    }

    /// Build a preset from events, rebased so earliest start = 0.
    public static func makePreset(id: String, name: String, from events: [HapticEvent]) -> HapticPreset? {
        guard let first = events.map(\.start).min() else { return nil }
        let rebased = events.sorted { $0.start < $1.start }.map { e -> HapticEvent in
            var n = e
            n.start = e.start - first
            n.presetID = nil
            n.generatedBy = nil
            return n
        }
        return HapticPreset(id: id, name: name, isBuiltIn: false, events: rebased)
    }

    /// Copies of events shifted right by their group span, fresh IDs.
    public static func duplicate(_ events: [HapticEvent]) -> [HapticEvent] {
        guard let first = events.map(\.start).min(), let last = events.map(\.end).max() else { return [] }
        let shift = last - first
        return events.map { e in
            var n = e
            n.id = UUID()
            n.start += shift
            n.generatedBy = nil
            return n
        }
    }
}
