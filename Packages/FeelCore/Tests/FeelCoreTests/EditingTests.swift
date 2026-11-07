// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class EditingTests: XCTestCase {
    func testHistoryUndoRedo() {
        var h = EditHistory<[Int]>()
        h.record([1])
        h.record([1, 2])
        XCTAssertEqual(h.undo(current: [1, 2, 3]), [1, 2])
        XCTAssertEqual(h.undo(current: [1, 2]), [1])
        XCTAssertNil(h.undo(current: [1]))
        XCTAssertEqual(h.redo(current: [1]), [1, 2])
        h.record([9])
        XCTAssertFalse(h.canRedo)
    }

    func testSnap() {
        XCTAssertEqual(EventEditing.snap(0.126, grid: 0.05), 0.15, accuracy: 1e-9)
        XCTAssertEqual(EventEditing.snap(0.126, grid: nil), 0.126)
    }

    func testMoveClampsAtZeroAndEnd() {
        var ev = [HapticEvent(type: .tap, start: 1), HapticEvent(type: .tap, start: 2)]
        let origins = Dictionary(uniqueKeysWithValues: ev.map { ($0.id, $0.start) })
        EventEditing.move(&ev, origins: origins, delta: -5, anchor: nil, grid: nil, duration: 10)
        XCTAssertEqual(ev.map(\.start), [0, 1])
        EventEditing.move(&ev, origins: origins, delta: 50, anchor: nil, grid: nil, duration: 10)
        XCTAssertEqual(ev[1].end, 10, accuracy: 1e-9)
        XCTAssertEqual(ev[1].start - ev[0].start, 1, accuracy: 1e-9)
    }

    func testMoveSnapsAnchor() {
        var ev = [HapticEvent(type: .tap, start: 1)]
        let origins = [ev[0].id: 1.0]
        EventEditing.move(&ev, origins: origins, delta: 0.512, anchor: ev[0].id, grid: 0.1, duration: 0)
        XCTAssertEqual(ev[0].start, 1.5, accuracy: 1e-9)
    }

    func testMakePresetRebases() {
        let ev = [HapticEvent(type: .tap, start: 3), HapticEvent(type: .tap, start: 3.5)]
        let p = EventEditing.makePreset(id: "c1", name: "C", from: ev)
        XCTAssertEqual(p?.events.map(\.start), [0, 0.5])
        XCTAssertEqual(p?.isBuiltIn, false)
    }

    func testDuplicateShiftsByGroupSpan() {
        let ev = [HapticEvent(type: .rumble, start: 1, duration: 2)]
        let d = EventEditing.duplicate(ev)
        XCTAssertEqual(d[0].start, 3, accuracy: 1e-9)
        XCTAssertNotEqual(d[0].id, ev[0].id)
    }

    func testTickTrainEffectiveDuration() {
        let e = HapticEvent(type: .tickTrain, start: 0, repetitionInterval: 0.1, repetitionCount: 5)
        XCTAssertEqual(e.effectiveDuration, 0.45, accuracy: 1e-9)
    }
}
