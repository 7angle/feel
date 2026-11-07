// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class ShareTests: XCTestCase {
    private func project() -> HapticProject {
        var p = HapticProject(name: "Clip")
        p.video = VideoReference(url: URL(fileURLWithPath: "/v/clip.mp4"), bookmark: nil,
                                 metadata: VideoMetadata(duration: 20, frameRate: 24, width: 1920, height: 1080))
        p.events = HapticPresetLibrary.preset(id: "explosion", custom: [])!.instantiate(at: 2)
            + HapticPresetLibrary.preset(id: "heartbeat", custom: [])!.instantiate(at: 8)
        return p
    }

    func testRoundTripKeepsEvents() throws {
        let p = project()
        let doc = try HapticShare.decode(ExportEngine.json(p))
        let events = HapticShare.events(from: doc)
        XCTAssertEqual(events.count, p.events.count)
        let sorted = p.events.sorted { $0.start < $1.start }
        for (a, b) in zip(events, sorted) {
            XCTAssertEqual(a.type, b.type)
            XCTAssertEqual(a.start, b.start, accuracy: 1e-9)
            XCTAssertEqual(a.intensity, b.intensity, accuracy: 1e-9)
            XCTAssertEqual(a.intensityCurve, b.intensityCurve)
            XCTAssertNotEqual(a.id, b.id)
        }
    }

    func testRejectsOtherJSON() {
        XCTAssertThrowsError(try HapticShare.decode(Data("{\"a\":1}".utf8))) {
            XCTAssertEqual($0 as? HapticShareError, .notHapticFile)
        }
    }

    func testRejectsNewerVersion() throws {
        var doc = HapticShare.events(from: try HapticShare.decode(ExportEngine.json(project()))).isEmpty
            ? nil : try HapticShare.decode(ExportEngine.json(project()))
        doc?.version = 99
        let data = try ProjectCoding.encoder().encode(try XCTUnwrap(doc))
        XCTAssertThrowsError(try HapticShare.decode(data)) {
            XCTAssertEqual($0 as? HapticShareError, .unsupportedVersion(99))
        }
    }

    func testMatch() throws {
        let doc = try HapticShare.decode(ExportEngine.json(project()))
        let same = VideoMetadata(duration: 20.2, frameRate: 24, width: 1920, height: 1080)
        let other = VideoMetadata(duration: 31, frameRate: 24, width: 1920, height: 1080)
        XCTAssertEqual(HapticShare.match(doc, video: same), .match)
        XCTAssertEqual(HapticShare.match(doc, video: other), .lengthDiffers(expected: 20, actual: 31))
        var noVideo = project()
        noVideo.video = nil
        let bare = try HapticShare.decode(ExportEngine.json(noVideo))
        XCTAssertEqual(HapticShare.match(bare, video: same), .unknown)
    }
}
