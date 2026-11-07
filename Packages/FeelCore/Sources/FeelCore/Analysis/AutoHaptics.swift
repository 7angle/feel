// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Builds haptics from audio and video together. Android has a port, `AutoHaptics.kt`.
/// Moments found in the video are the base. Audio gives them exact times.
/// Audio hits with no matching motion stay, but they are weaker and farther apart.
public enum AutoHaptics {
    /// Widest distance between a video moment and the audio hit it snaps to.
    /// Video samples are 67 ms apart, so this allows for one sample and some delay.
    static let snapRadius = 0.12
    /// Smallest gap between two taps that the video confirms.
    static let confirmedGap = 0.2
    /// A tap with no matching motion is this much weaker, but stays strong enough to feel on an iPhone.
    static let audioOnlyScale = 0.7
    static let audioOnlyFloor = 0.5

    public static func generate(spectrum: AudioSpectrum, input: AnalysisInput, sensitivity: Double) -> [HapticEvent] {
        let s = min(max(sensitivity, 0), 1)
        let suggestions = HeuristicSuggester().suggest(input, sensitivity: s)
        let audio = AudioHaptics.generate(spectrum: spectrum, sensitivity: s)
        let audioTaps = audio.filter { $0.type == .tap }

        var out: [HapticEvent] = []
        var taps: [HapticEvent] = []

        // Explosions and impacts always stay. They move to the nearest audio hit.
        for suggestion in suggestions where suggestion.kind == .explosion || suggestion.kind == .impact {
            let hit = nearest(audioTaps, to: suggestion.time)
            let delta = hit.map { $0.start - suggestion.time } ?? 0
            for var event in suggestion.events {
                event.start = max(0, event.start + delta)
                if event.type == .tap {
                    if suggestion.kind == .impact, let hit {
                        event.intensity = max(event.intensity, hit.intensity)
                        event.sharpness = hit.sharpness
                    }
                    taps.append(event)
                } else {
                    out.append(event)
                }
            }
        }

        // Audio hits that the video confirms come next, then the others. Strongest hits go first.
        let motion = MotionCheck(features: input.features, sensitivity: s)
        let strongest = audioTaps.sorted { ($0.intensity, $1.start) > ($1.intensity, $0.start) }
        for tap in strongest where motion.confirms(tap.start) && isClear(tap.start, of: taps, gap: confirmedGap) {
            taps.append(tap)
        }
        let audioOnlyGap = 1 / (0.5 + s)
        for var tap in strongest where !motion.confirms(tap.start) && isClear(tap.start, of: taps, gap: audioOnlyGap) {
            tap.intensity = max(tap.intensity * audioOnlyScale, audioOnlyFloor)
            taps.append(tap)
        }
        out.append(contentsOf: taps)

        // Rumbles. The first in this order wins when two cover the same time.
        func motionRumbles(_ kind: SuggestionKind) -> [HapticEvent] {
            suggestions.filter { $0.kind == kind }.flatMap(\.events)
        }
        let rumbles = motionRumbles(.highAction) + audio.filter { $0.type == .rumble }
            + motionRumbles(.cameraShake) + motionRumbles(.fastMovement)
        var kept = out.filter { $0.type == .rumble }
        for rumble in rumbles where !mostlyCovered(rumble, by: kept) {
            kept.append(rumble)
            out.append(rumble)
        }

        return out.sorted { $0.start < $1.start }.map { event in
            var marked = event
            marked.id = UUID()
            marked.generatedBy = AudioHaptics.generatorID
            return marked
        }
    }

    // MARK: Rules

    private static func nearest(_ taps: [HapticEvent], to time: TimelineTime) -> HapticEvent? {
        taps.filter { abs($0.start - time) <= snapRadius }
            .min { abs($0.start - time) < abs($1.start - time) }
    }

    private static func isClear(_ time: TimelineTime, of taps: [HapticEvent], gap: Double) -> Bool {
        !taps.contains { abs($0.start - time) < gap }
    }

    private static func mostlyCovered(_ rumble: HapticEvent, by others: [HapticEvent]) -> Bool {
        others.contains { other in
            let overlap = min(rumble.end, other.end) - max(rumble.start, other.start)
            return overlap > rumble.duration / 2
        }
    }

    /// Tells if the picture has a sudden change near a given time.
    private struct MotionCheck {
        let features: [FrameFeature]
        let z: [Double]
        let threshold: Double
        let step: Double

        init(features: [FrameFeature], sensitivity: Double) {
            self.features = features
            z = HeuristicSuggester.zscores(features.map(\.motion), floor: 0.01)
            threshold = (7 - 5 * sensitivity) * 0.6
            step = features.count > 1 ? (features[features.count - 1].t - features[0].t) / Double(features.count - 1) : 0
        }

        func confirms(_ time: TimelineTime) -> Bool {
            guard features.count > 6, step > 0 else { return false }
            let center = Int(((time - features[0].t) / step).rounded())
            let lo = center - 2, hi = center + 2
            guard lo >= 4, hi < features.count else { return false }
            let before = features[lo - 4..<lo].reduce(0) { $0 + $1.motion } / 4
            return (lo...hi).contains { i in
                z[i] > threshold && features[i].motion > 0.03 && features[i].motion > 1.4 * before + 0.01
            }
        }
    }
}
