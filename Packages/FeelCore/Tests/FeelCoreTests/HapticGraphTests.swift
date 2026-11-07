// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class HapticGraphTests: XCTestCase {
    func testEmptyWithoutEventsOrLength() {
        XCTAssertEqual(HapticGraph.levels(events: [], duration: 10), [])
        XCTAssertEqual(HapticGraph.levels(events: [HapticEvent(type: .tap, start: 1)], duration: 0), [])
    }

    func testPeaksWhereHapticsAreDense() {
        let dense = (0..<10).map { HapticEvent(type: .tap, start: 75 + Double($0) * 0.1) }
        let levels = HapticGraph.levels(events: [HapticEvent(type: .tap, start: 10)] + dense, duration: 100, count: 100)
        XCTAssertEqual(levels.count, 100)
        XCTAssertEqual(levels.max(), 1)
        XCTAssertEqual(levels[75], 1, accuracy: 0.2)
        XCTAssertLessThan(levels[10], 0.3)
        XCTAssertEqual(levels[40], 0)
    }

    func testFallsToZeroAtBothEnds() {
        let events = (0..<100).map { HapticEvent(type: .tap, start: Double($0)) }
        let levels = HapticGraph.levels(events: events, duration: 100, count: 100)
        XCTAssertEqual(levels.first, 0)
        XCTAssertEqual(levels.last, 0)
        XCTAssertGreaterThan(levels[50], 0.5)
    }

    func testEventPastTheEndIsIgnored() {
        XCTAssertEqual(HapticGraph.levels(events: [HapticEvent(type: .tap, start: 20)], duration: 10), [])
    }
}
