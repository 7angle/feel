// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import CoreMedia
import Foundation

/// Monotonic host clock in seconds. Same clock AVPlayer uses for `setRate(_:time:atHostTime:)`.
public enum SharedClock {
    public static func now() -> TimeInterval {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}

/// NTP-style offset estimate. `peerTime = localTime + offset`.
/// Keeps recent samples and trusts the lowest round trip.
public struct ClockSync: Sendable {
    public struct Sample: Sendable, Equatable {
        public var offset: Double
        public var rtt: Double
    }

    public private(set) var samples: [Sample] = []
    public let capacity: Int

    public init(capacity: Int = 16) { self.capacity = capacity }

    /// t0 local send, t1 peer receive, t2 peer send, t3 local receive.
    public mutating func add(t0: Double, t1: Double, t2: Double, t3: Double) {
        let rtt = (t3 - t0) - (t2 - t1)
        guard rtt >= 0 else { return }
        let offset = ((t1 - t0) + (t2 - t3)) / 2
        samples.append(Sample(offset: offset, rtt: rtt))
        if samples.count > capacity { samples.removeFirst() }
    }

    private var best: Sample? { samples.min { $0.rtt < $1.rtt } }
    public var offset: Double? { best?.offset }
    public var rtt: Double? { best?.rtt }

    public func localTime(forPeer peer: Double) -> Double? { offset.map { peer - $0 } }
    public mutating func reset() { samples.removeAll() }
}
