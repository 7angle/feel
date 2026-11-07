// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class ModelTests: XCTestCase {
    func sampleProject() -> HapticProject {
        var p = HapticProject(name: "Test")
        p.video = VideoReference(url: URL(fileURLWithPath: "/tmp/a.mp4"), bookmark: nil,
                                 metadata: VideoMetadata(duration: 12.5, frameRate: 29.97, width: 1920, height: 1080))
        p.events = HapticPresetLibrary.builtIn.flatMap { $0.instantiate(at: 1) }
        return p
    }

    func testProjectRoundTrip() throws {
        let p = sampleProject()
        let back = try ProjectCoding.decode(try ProjectCoding.encode(p))
        XCTAssertEqual(p.events, back.events)
        XCTAssertEqual(p.video, back.video)
        XCTAssertEqual(p.name, back.name)
    }

    func testStoreSaveLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).feelproj")
        defer { try? FileManager.default.removeItem(at: url) }
        let p = sampleProject()
        try ProjectStore().save(p, to: url)
        let back = try ProjectStore().load(from: url)
        XCTAssertEqual(back.id, p.id)
        XCTAssertEqual(back.events.count, p.events.count)
    }

    func testFutureVersionRejected() throws {
        var p = sampleProject()
        p.version = 99
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(UUID()).feelproj")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectCoding.encode(p).write(to: url)
        XCTAssertThrowsError(try ProjectStore().load(from: url))
    }

    func testMissingVideo() {
        let ref = VideoReference(url: URL(fileURLWithPath: "/nope/missing.mp4"), bookmark: nil,
                                 metadata: VideoMetadata(duration: 1, frameRate: 30, width: 1, height: 1))
        XCTAssertEqual(ProjectStore().resolveVideo(ref).resolution, .missing(lastKnown: ref.url))
    }

    func testDuplicateNewID() {
        let p = sampleProject()
        let d = ProjectStore().duplicate(p, name: "Copy")
        XCTAssertNotEqual(p.id, d.id)
        XCTAssertEqual(d.events, p.events)
    }

    func testNormalizeClamps() {
        let e = HapticEvent(type: .rumble, start: -1, duration: 1, intensity: 3, sharpness: -2, repetitionCount: 0, fadeIn: 5, fadeOut: 5).normalized()
        XCTAssertEqual(e.start, 0)
        XCTAssertEqual(e.intensity, 1)
        XCTAssertEqual(e.sharpness, 0)
        XCTAssertEqual(e.repetitionCount, 1)
        XCTAssertLessThanOrEqual(e.fadeIn + e.fadeOut, e.duration)
    }

    func testPresetInstantiateOffsets() {
        let p = HapticPresetLibrary.preset(id: "double-tap", custom: [])!
        let ev = p.instantiate(at: 2)
        XCTAssertEqual(ev.map(\.start), [2, 2.12])
        XCTAssertTrue(ev.allSatisfy { $0.presetID == "double-tap" })
    }

    func testTimebaseFormat() {
        XCTAssertEqual(Timebase.format(65.25), "01:05.250")
    }
}

final class JoinLinkTests: XCTestCase {
    func testRoundTrip() {
        let l = JoinLink(host: "192.168.1.2", port: 51234, code: "123456", name: "Naveen's Mac")
        XCTAssertEqual(JoinLink(url: l.url), l)
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(JoinLink(url: "https://example.com"))
        XCTAssertNil(JoinLink(url: "feel://join?host=1.2.3.4&port=1&code=12"))
    }
}

final class HapticLevelTests: XCTestCase {
    func testTapDecays() {
        let e = HapticEvent(type: .tap, start: 1, intensity: 0.8)
        XCTAssertEqual(e.level(at: 0.99), 0)
        XCTAssertEqual(e.level(at: 1), 0.8, accuracy: 0.001)
        XCTAssertEqual(e.level(at: 1.06), 0.4, accuracy: 0.001)
        XCTAssertEqual(e.level(at: 1.2), 0)
    }

    func testRumbleFollowsFadesAndCurve() {
        let faded = HapticEvent(type: .rumble, start: 0, duration: 1, intensity: 1, fadeIn: 0.5)
        XCTAssertEqual(faded.level(at: 0.25), 0.5, accuracy: 0.001)
        XCTAssertEqual(faded.level(at: 0.75), 1, accuracy: 0.001)
        XCTAssertEqual(faded.level(at: 1.5), 0)
        let curved = HapticEvent(type: .rumble, start: 0, duration: 1, intensity: 1, intensityCurve: [CurvePoint(time: 0, value: 0), CurvePoint(time: 1, value: 1)])
        XCTAssertEqual(curved.level(at: 0.5), 0.5, accuracy: 0.001)
    }

    func testTickTrainStopsAfterLastTick() {
        let e = HapticEvent(type: .tickTrain, start: 0, intensity: 1, repetitionInterval: 0.1, repetitionCount: 2)
        XCTAssertEqual(e.level(at: 0.1), 1, accuracy: 0.001)
        XCTAssertEqual(e.level(at: 0.25), 0)
    }

    func testStrongestEventWins() {
        let events = [HapticEvent(type: .tap, start: 0, intensity: 0.3), HapticEvent(type: .tap, start: 0, intensity: 0.9)]
        XCTAssertEqual(events.level(at: 0), 0.9, accuracy: 0.001)
    }
}
