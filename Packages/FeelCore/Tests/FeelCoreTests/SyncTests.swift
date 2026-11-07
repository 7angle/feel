// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class SyncTests: XCTestCase {
    func testOffsetSymmetricLatency() {
        var c = ClockSync()
        // peer clock = local + 100. one-way 5ms each way.
        c.add(t0: 10, t1: 110.005, t2: 110.006, t3: 10.011)
        XCTAssertEqual(c.offset ?? 0, 100, accuracy: 1e-6)
        XCTAssertEqual(c.rtt ?? 0, 0.010, accuracy: 1e-6)
    }

    func testPrefersLowestRTT() {
        var c = ClockSync()
        c.add(t0: 0, t1: 100.2, t2: 100.2, t3: 0.4)   // rtt .4, skewed offset
        c.add(t0: 1, t1: 101.005, t2: 101.005, t3: 1.01) // rtt .01
        XCTAssertEqual(c.rtt ?? 1, 0.01, accuracy: 1e-9)
        XCTAssertEqual(c.offset ?? 0, 100, accuracy: 0.01)
    }

    func testRejectsNegativeRTT() {
        var c = ClockSync()
        c.add(t0: 5, t1: 0, t2: 100, t3: 6)
        XCTAssertNil(c.offset)
    }

    func testLocalTimeConversion() {
        var c = ClockSync()
        c.add(t0: 0, t1: 50, t2: 50, t3: 0)
        XCTAssertEqual(c.localTime(forPeer: 60) ?? 0, 10, accuracy: 1e-9)
    }

    func testMessageRoundTrip() throws {
        let msgs: [Message] = [
            .hello(Hello(name: "Mac", role: .editor, supportsHaptics: false)),
            .ping(id: 3, t0: 1.5),
            .pong(id: 3, t0: 1.5, t1: 2, t2: 2.1),
            .pattern(revision: 4, events: [HapticEvent(type: .rumble, start: 1, duration: 2)]),
            .play(mediaTime: 3, hostTime: 99.5, advance: 0.01),
            .pause(mediaTime: 4),
            .audition(HapticEvent(type: .tap, start: 0)),
            .status(CompanionStatus(playing: true, engineReady: true, rtt: 0.01)),
            .bye,
        ]
        for m in msgs {
            let data = try m.encoded()
            XCTAssertEqual(data.last, 0x0A)
            XCTAssertFalse(data.dropLast().contains(0x0A))
            XCTAssertEqual(try Message.decode(data.dropLast()), m)
        }
    }

    func testSharedClockMonotonic() {
        let a = SharedClock.now()
        let b = SharedClock.now()
        XCTAssertGreaterThanOrEqual(b, a)
    }
}

final class PlanTests: XCTestCase {
    func testFutureStartKeepsMediaStart() {
        // editor plays media 10 at editor t=100. local = editor - 50. now local 49.5 => start in 0.5s.
        let p = PlaybackPlan.make(mediaTime: 10, editorHostTime: 100, advance: 0, clockOffset: 50, nowLocal: 49.5)
        XCTAssertEqual(p.mediaStart, 10, accuracy: 1e-9)
        XCTAssertEqual(p.delay, 0.5, accuracy: 1e-9)
    }

    func testLateStartSkipsAhead() {
        let p = PlaybackPlan.make(mediaTime: 10, editorHostTime: 100, advance: 0, clockOffset: 50, nowLocal: 51)
        XCTAssertEqual(p.delay, 0.03, accuracy: 1e-9)
        XCTAssertEqual(p.mediaStart, 10 + 1.03, accuracy: 1e-9)
    }

    func testAdvanceMovesHapticsEarlier() {
        let a = PlaybackPlan.make(mediaTime: 0, editorHostTime: 100, advance: 0.05, clockOffset: 0, nowLocal: 99)
        XCTAssertEqual(a.delay, 0.95, accuracy: 1e-9)
    }

    func testPositionMatchesPlan() {
        let pos = PlaybackPlan.position(mediaTime: 5, editorHostTime: 20, advance: 0, clockOffset: 0, nowLocal: 22)
        XCTAssertEqual(pos, 7, accuracy: 1e-9)
    }

    func testOldProjectWithoutAdvanceDecodes() throws {
        let json = #"{"snapToGrid":false,"gridInterval":0.1,"autosave":true}"#
        let s = try JSONDecoder().decode(ProjectSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.hapticAdvance, 0)
        XCTAssertFalse(s.snapToGrid)
    }
}
