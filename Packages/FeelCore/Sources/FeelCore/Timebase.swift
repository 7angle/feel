// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Single timeline timebase: seconds from video start, as Double.
public typealias TimelineTime = Double

public enum Timebase {
    /// Clamp time into [0, duration].
    public static func clamp(_ t: TimelineTime, duration: TimelineTime) -> TimelineTime {
        min(max(t, 0), max(duration, 0))
    }

    /// Format as mm:ss.mmm.
    public static func format(_ t: TimelineTime) -> String {
        let t = max(t, 0)
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t - floor(t)) * 1000)
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }

    /// Format for a video player: m:ss, or h:mm:ss for a long video.
    public static func clock(_ t: TimelineTime) -> String {
        let total = Int(max(t, 0))
        let h = total / 3600
        let m = total % 3600 / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
