// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class ExportTests: XCTestCase {
    private func project() -> HapticProject {
        var p = HapticProject(name: "My Trailer: Cut 1")
        p.video = VideoReference(url: URL(fileURLWithPath: "/v/clip.mp4"), bookmark: nil,
                                 metadata: VideoMetadata(duration: 20, frameRate: 24, width: 3840, height: 2160))
        p.events = HapticPresetLibrary.preset(id: "explosion", custom: [])!.instantiate(at: 2)
            + HapticPresetLibrary.preset(id: "heartbeat", custom: [])!.instantiate(at: 8)
        return p
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("feel-\(UUID())")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testJSONContainsRequiredFields() throws {
        let data = try ExportEngine.json(project())
        let doc = try ProjectCoding.decoder().decode(HapticExportDocument.self, from: data)
        XCTAssertEqual(doc.format, "feel-haptics")
        XCTAssertEqual(doc.video?.width, 3840)
        XCTAssertEqual(doc.video?.frameRate, 24)
        XCTAssertEqual(doc.timelineDuration, 20)
        XCTAssertEqual(doc.events.count, 6)
        XCTAssertEqual(doc.events.first?.presetName, "Explosion")
        XCTAssertEqual(Set(doc.presets.map(\.id)), ["explosion", "heartbeat"])
        XCTAssertFalse(doc.events.filter { $0.type == .rumble }.allSatisfy { $0.intensityCurve.isEmpty })
    }

    func testAHAPPreservesTimingIntensitySharpness() throws {
        var p = HapticProject(name: "t")
        p.events = [HapticEvent(type: .tap, start: 3.25, intensity: 0.6, sharpness: 0.15)]
        let obj = try JSONSerialization.jsonObject(with: try ExportEngine.ahap(p)) as? [String: Any]
        let item = (obj?["Pattern"] as? [[String: Any]])?.first?["Event"] as? [String: Any]
        XCTAssertEqual(item?["Time"] as? Double, 3.25)
        let params = item?["EventParameters"] as? [[String: Any]]
        XCTAssertEqual(params?.first { $0["ParameterID"] as? String == "HapticIntensity" }?["ParameterValue"] as? Double, 0.6)
        XCTAssertEqual(params?.first { $0["ParameterID"] as? String == "HapticSharpness" }?["ParameterValue"] as? Double, 0.15)
    }

    func testWriteAllFormats() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try ExportEngine.write(project(), formats: Set(ExportFormat.allCases), to: dir)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["My_Trailer__Cut_1.ahap", "My_Trailer__Cut_1.json", "FeelHapticVideoSync.swift", "FeelHapticVideoSync.kt"])
        let swift = try String(contentsOf: dir.appendingPathComponent("FeelHapticVideoSync.swift"), encoding: .utf8)
        XCTAssertTrue(swift.contains("My_Trailer__Cut_1"))
        XCTAssertFalse(swift.contains("__AHAP_NAME__"))
        let kotlin = try String(contentsOf: dir.appendingPathComponent("FeelHapticVideoSync.kt"), encoding: .utf8)
        XCTAssertTrue(kotlin.contains("My_Trailer__Cut_1.json"))
        XCTAssertFalse(kotlin.contains("__JSON_NAME__"))
        for u in urls where u.pathExtension == "ahap" || u.pathExtension == "json" {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: u)))
        }
    }

    func testKotlinExportWritesTheJSONItNeeds() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try ExportEngine.write(project(), formats: [.kotlin], to: dir)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["My_Trailer__Cut_1.json", "FeelHapticVideoSync.kt"])
    }

    /// The Android unit tests compile and run this copy of the generated Kotlin.
    /// Run to update: FEEL_GOLDEN_DIR=Apps/FeelAndroid/app/src/test/resources swift test --filter testKotlinFixtureIsCurrent
    func testKotlinFixtureIsCurrent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("Apps/FeelAndroid/app/src/test/java/com/feelplayer/haptics/FeelHapticVideoSync.kt")
        let source = KotlinPlaybackTemplate.source(jsonName: "share-golden")
        if ProcessInfo.processInfo.environment["FEEL_GOLDEN_DIR"] != nil {
            try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: fixture, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: fixture, encoding: .utf8), source)
    }

    func testEmptyProjectBlocksExport() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try ExportEngine.write(HapticProject(name: "x"), formats: [.ahap], to: dir)) {
            XCTAssertEqual($0 as? ExportError, .validation(["No haptic events to export."]))
        }
    }

    func testValidationWarnings() {
        var p = project()
        p.events.append(HapticEvent(type: .tap, start: 50, intensity: 0))
        let issues = ExportEngine.validate(p)
        XCTAssertFalse(ExportEngine.hasErrors(issues))
        XCTAssertTrue(issues.contains { $0.message.contains("after the video ends") })
        XCTAssertTrue(issues.contains { $0.message.contains("zero intensity") })
    }

    func testGeneratedSwiftTypechecksForIOS() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Gen.swift")
        try SwiftPlaybackTemplate.source(ahapName: "demo").write(to: file, atomically: true, encoding: .utf8)
        let sdk = Process()
        sdk.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        sdk.arguments = ["--sdk", "iphonesimulator", "--show-sdk-path"]
        let pipe = Pipe()
        sdk.standardOutput = pipe
        do { try sdk.run() } catch { throw XCTSkip("xcrun unavailable") }
        sdk.waitUntilExit()
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sdk.terminationStatus == 0, !path.isEmpty else { throw XCTSkip("iOS SDK unavailable") }

        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        c.arguments = ["swiftc", "-typecheck", "-sdk", path, "-target", "arm64-apple-ios16.0-simulator", file.path]
        let err = Pipe()
        c.standardError = err
        try c.run()
        c.waitUntilExit()
        let log = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(c.terminationStatus, 0, log)
    }
}
