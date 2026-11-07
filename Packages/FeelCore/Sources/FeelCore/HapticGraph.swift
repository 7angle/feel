// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// How much haptic there is along a video, for the graph over a timeline.
public enum HapticGraph {
    /// One value per slot, from 0 to 1, smoothed, and falling to 0 at both ends. Empty if there is nothing to show.
    public static func levels(events: [HapticEvent], duration: TimelineTime, count: Int = 96) -> [Double] {
        guard duration > 0, count > 0, !events.isEmpty else { return [] }
        var slots = [Double](repeating: 0, count: count)
        let slot = { (t: TimelineTime) in min(max(Int(t / duration * Double(count)), 0), count - 1) }
        for event in events where event.start < duration {
            for i in slot(event.start)...slot(event.end) { slots[i] += event.intensity }
        }
        for _ in 0..<3 {
            let previous = slots
            for i in 0..<count {
                let near = previous[max(i - 3, 0)...min(i + 3, count - 1)]
                slots[i] = near.reduce(0, +) / Double(near.count)
            }
        }
        guard let top = slots.max(), top > 0 else { return [] }
        return slots.indices.map { i in
            let edge = min(Double(min(i, count - 1 - i)) / 4, 1)
            return slots[i] / top * edge * edge * (3 - 2 * edge)
        }
    }
}
