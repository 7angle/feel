// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Per-sample measurements from video. Values are resolution independent.
public struct FrameFeature: Equatable, Sendable {
    public var t: TimelineTime
    /// Mean luma 0...1.
    public var luma: Double
    /// Histogram distance to previous sample 0...1. Spikes on hard cuts.
    public var histDiff: Double
    /// Mean absolute luma change to previous sample 0...1.
    public var motion: Double
    /// Estimated global shift in analysis pixels.
    public var shiftX: Double
    public var shiftY: Double
    /// Fraction of near-white pixels 0...1.
    public var bright: Double

    public init(t: TimelineTime, luma: Double = 0.3, histDiff: Double = 0, motion: Double = 0, shiftX: Double = 0, shiftY: Double = 0, bright: Double = 0) {
        self.t = t
        self.luma = luma
        self.histDiff = histDiff
        self.motion = motion
        self.shiftX = shiftX
        self.shiftY = shiftY
        self.bright = bright
    }
}

public struct AnalysisInput: Sendable {
    public var features: [FrameFeature]
    /// Audio peaks, `AudioEnvelope.bucketsPerSecond` per second. Empty = no audio.
    public var audio: [Float]
    public var duration: TimelineTime

    public init(features: [FrameFeature], audio: [Float], duration: TimelineTime) {
        self.features = features
        self.audio = audio
        self.duration = duration
    }
}

public enum SuggestionKind: String, Codable, CaseIterable, Sendable {
    case sceneCut, impact, explosion, fastMovement, cameraShake, highAction

    public var title: String {
        switch self {
        case .sceneCut: "Scene cut"
        case .impact: "Impact"
        case .explosion: "Explosion"
        case .fastMovement: "Fast movement"
        case .cameraShake: "Camera shake"
        case .highAction: "High action"
        }
    }
}

/// Proposed haptics. Never applied without the user's consent.
public struct HapticSuggestion: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: SuggestionKind
    public var time: TimelineTime
    public var duration: TimelineTime
    /// 0...1. Confidence and size of the moment.
    public var strength: Double
    public var reason: String
    /// Events at absolute timeline positions.
    public var events: [HapticEvent]

    public init(kind: SuggestionKind, time: TimelineTime, duration: TimelineTime = 0, strength: Double, reason: String, events: [HapticEvent]) {
        self.kind = kind
        self.time = time
        self.duration = duration
        self.strength = strength
        self.reason = reason
        self.events = events
    }
}

/// Turns measurements into suggestions. Swap in an ML implementation later.
public protocol HapticSuggester: Sendable {
    /// `sensitivity` 0...1. Higher finds more.
    func suggest(_ input: AnalysisInput, sensitivity: Double) -> [HapticSuggestion]
}
