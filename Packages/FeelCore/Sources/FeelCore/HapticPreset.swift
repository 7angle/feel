// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public struct HapticPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    /// Events with start relative to preset origin (0).
    public var events: [HapticEvent]

    public init(id: String, name: String, isBuiltIn: Bool, events: [HapticEvent]) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.events = events
    }

    /// Instantiate at `time` with fresh IDs.
    public func instantiate(at time: TimelineTime) -> [HapticEvent] {
        events.map { e in
            var n = e
            n.id = UUID()
            n.start = time + e.start
            n.presetID = id
            return n
        }
    }

    public var span: TimelineTime { events.map(\.end).max() ?? 0 }
}

public enum HapticPresetLibrary {
    private static func tap(_ t: TimelineTime, _ i: Double, _ s: Double) -> HapticEvent {
        HapticEvent(type: .tap, start: t, intensity: i, sharpness: s)
    }

    public static let builtIn: [HapticPreset] = [
        HapticPreset(id: "light-tap", name: "Light Tap", isBuiltIn: true, events: [tap(0, 0.35, 0.6)]),
        HapticPreset(id: "heavy-impact", name: "Heavy Impact", isBuiltIn: true, events: [tap(0, 1.0, 0.3)]),
        HapticPreset(id: "soft-pulse", name: "Soft Pulse", isBuiltIn: true, events: [
            HapticEvent(type: .rumble, start: 0, duration: 0.3, intensity: 0.45, sharpness: 0.1, fadeIn: 0.1, fadeOut: 0.15),
        ]),
        HapticPreset(id: "double-tap", name: "Double Tap", isBuiltIn: true, events: [tap(0, 0.7, 0.5), tap(0.12, 0.7, 0.5)]),
        HapticPreset(id: "machine-gun", name: "Machine Gun", isBuiltIn: true, events: [
            HapticEvent(type: .tickTrain, start: 0, intensity: 0.9, sharpness: 0.8, repetitionInterval: 0.06, repetitionCount: 12),
        ]),
        HapticPreset(id: "engine-rumble", name: "Engine Rumble", isBuiltIn: true, events: [
            HapticEvent(type: .rumble, start: 0, duration: 1.5, intensity: 0.6, sharpness: 0.15,
                        intensityCurve: [CurvePoint(time: 0, value: 0.7), CurvePoint(time: 0.4, value: 1), CurvePoint(time: 0.8, value: 0.75), CurvePoint(time: 1.2, value: 1), CurvePoint(time: 1.5, value: 0.8)]),
        ]),
        HapticPreset(id: "explosion", name: "Explosion", isBuiltIn: true, events: [
            tap(0, 1.0, 0.9),
            HapticEvent(type: .rumble, start: 0.02, duration: 1.0, intensity: 1.0, sharpness: 0.2, fadeOut: 0.9,
                        intensityCurve: [CurvePoint(time: 0, value: 1), CurvePoint(time: 0.3, value: 0.6), CurvePoint(time: 1.0, value: 0)]),
        ]),
        HapticPreset(id: "heartbeat", name: "Heartbeat", isBuiltIn: true, events: [
            tap(0, 0.9, 0.2), tap(0.15, 0.6, 0.2), tap(0.8, 0.9, 0.2), tap(0.95, 0.6, 0.2),
        ]),
        HapticPreset(id: "notification", name: "Notification", isBuiltIn: true, events: [
            tap(0, 0.6, 0.7), tap(0.1, 0.6, 0.7), tap(0.3, 0.9, 0.9),
        ]),
        HapticPreset(id: "metallic-impact", name: "Metallic Impact", isBuiltIn: true, events: [
            tap(0, 1.0, 1.0),
            HapticEvent(type: .rumble, start: 0.01, duration: 0.35, intensity: 0.5, sharpness: 0.95, fadeOut: 0.3),
        ]),
        HapticPreset(id: "rapid-ticks", name: "Rapid Ticks", isBuiltIn: true, events: [
            HapticEvent(type: .tickTrain, start: 0, intensity: 0.5, sharpness: 0.9, repetitionInterval: 0.04, repetitionCount: 20),
        ]),
    ]

    public static func all(custom: [HapticPreset]) -> [HapticPreset] { builtIn + custom }

    public static func preset(id: String, custom: [HapticPreset]) -> HapticPreset? {
        all(custom: custom).first { $0.id == id }
    }
}
