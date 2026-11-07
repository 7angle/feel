// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Maps "media time m0 plays at editor host time h0" onto the companion's local clock.
public struct PlaybackPlan: Equatable, Sendable {
    /// Media time where the pattern must begin.
    public var mediaStart: TimelineTime
    /// Seconds from `nowLocal` until pattern starts.
    public var delay: TimeInterval

    /// - Parameters:
    ///   - clockOffset: editorTime = localTime + clockOffset.
    ///   - advance: play haptics this many seconds early (hardware latency).
    ///   - lead: minimum delay needed to schedule on the engine.
    public static func make(
        mediaTime: TimelineTime, editorHostTime: TimeInterval, advance: TimeInterval,
        clockOffset: TimeInterval, nowLocal: TimeInterval, lead: TimeInterval = 0.03
    ) -> PlaybackPlan {
        let startLocal = (editorHostTime - clockOffset) - advance
        if startLocal >= nowLocal + lead {
            return PlaybackPlan(mediaStart: mediaTime, delay: startLocal - nowLocal)
        }
        let elapsed = nowLocal + lead - startLocal
        return PlaybackPlan(mediaStart: mediaTime + elapsed, delay: lead)
    }

    /// Media position at `nowLocal` for a given transport. Used for drift checks.
    public static func position(
        mediaTime: TimelineTime, editorHostTime: TimeInterval, advance: TimeInterval,
        clockOffset: TimeInterval, nowLocal: TimeInterval
    ) -> TimelineTime {
        mediaTime + (nowLocal - ((editorHostTime - clockOffset) - advance))
    }
}
