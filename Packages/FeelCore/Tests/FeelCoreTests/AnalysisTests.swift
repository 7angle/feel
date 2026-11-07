// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import XCTest
@testable import FeelCore

final class AnalysisTests: XCTestCase {
    private let dt = 1.0 / 15

    /// Quiet baseline with small random-ish motion.
    private func baseline(seconds: Double = 10) -> [FrameFeature] {
        (0..<Int(seconds * 15)).map { i in
            FrameFeature(t: Double(i) * dt, luma: 0.35, histDiff: 0.01, motion: 0.01 + 0.002 * Double(i % 3))
        }
    }

    private func kinds(_ s: [HapticSuggestion]) -> [SuggestionKind] { s.map(\.kind) }

    func testQuietVideoYieldsNothing() {
        let s = HeuristicSuggester().suggest(AnalysisInput(features: baseline(), audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertTrue(s.isEmpty)
    }

    func testHardCutDetected() {
        var f = baseline()
        f[60].histDiff = 0.9
        f[60].motion = 0.25
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertEqual(kinds(s), [.sceneCut])
        XCTAssertEqual(s[0].time, f[60].t, accuracy: 1e-9)
    }

    func testMotionSpikeWithAudioHitIsImpact() {
        var f = baseline()
        f[75].motion = 0.2
        var audio = [Float](repeating: 0.03, count: 1000)
        for i in 495..<520 { audio[i] = 0.95 }
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: audio, duration: 10), sensitivity: 0.5)
        XCTAssertEqual(kinds(s), [.impact])
        XCTAssertEqual(s[0].events.first?.type, .tap)
    }

    func testMotionSpikeAloneNeedsMoreEvidenceWithoutAudio() {
        var f = baseline()
        f[75].motion = 0.06
        XCTAssertTrue(HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5).isEmpty)
        f[75].motion = 0.4
        XCTAssertEqual(kinds(HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)), [.impact])
    }

    func testFlashWithMotionIsExplosion() {
        var f = baseline()
        for i in 60...64 { f[i].luma = 0.7; f[i].bright = 0.5 }
        f[60].motion = 0.3
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertEqual(kinds(s), [.explosion])
        XCTAssertGreaterThan(s[0].events.count, 1)
    }

    func testSustainedMotionBecomesRumble() {
        var f = baseline()
        for i in 45..<90 { f[i].motion = 0.12 }
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertEqual(kinds(s), [.fastMovement])
        XCTAssertEqual(s[0].duration, 44 * dt, accuracy: 0.2)
        XCTAssertEqual(s[0].events[0].type, .rumble)
    }

    func testSustainedMotionWithLoudAudioIsHighAction() {
        var f = baseline()
        for i in 45..<90 { f[i].motion = 0.12 }
        var audio = [Float](repeating: 0.03, count: 1000)
        for i in 300..<600 { audio[i] = 0.8 }
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: audio, duration: 10), sensitivity: 0.5)
        XCTAssertTrue(kinds(s).contains(.highAction))
        XCTAssertFalse(kinds(s).contains(.fastMovement))
        XCTAssertFalse(s.first { $0.kind == .highAction }!.events[0].intensityCurve.isEmpty)
    }

    func testShakeDetected() {
        var f = baseline()
        for i in 45..<90 { f[i].shiftX = i % 2 == 0 ? 3 : -3; f[i].shiftY = i % 2 == 0 ? -2 : 2 }
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertTrue(kinds(s).contains(.cameraShake))
    }

    func testSteadyPanIsNotShake() {
        var f = baseline()
        for i in 45..<90 { f[i].shiftX = 3 }
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertFalse(kinds(s).contains(.cameraShake))
    }

    func testLowerSensitivityFindsFewer() {
        var f = baseline()
        f[60].histDiff = 0.45
        let hi = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 1)
        let lo = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0)
        XCTAssertGreaterThan(hi.count, lo.count)
    }

    func testSuggestionsAreSortedAndHaveEvents() {
        var f = baseline()
        f[100].histDiff = 0.9
        f[40].histDiff = 0.9
        let s = HeuristicSuggester().suggest(AnalysisInput(features: f, audio: [], duration: 10), sensitivity: 0.5)
        XCTAssertEqual(s.map(\.time), s.map(\.time).sorted())
        XCTAssertTrue(s.allSatisfy { !$0.events.isEmpty })
    }

    // MARK: Real decode

    /// Writes a 4 s clip: dark gray, hard cut to white at 2 s.
    private func makeClip(at url: URL) async throws {
        let w = 320, h = 180, fps = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for n in 0..<(4 * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
            let buffer = try XCTUnwrap(pb)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), n < 2 * fps ? 40 : 250, CVPixelBufferGetBytesPerRow(buffer) * h)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    func testExtractorFindsCutInRealVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cut-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeClip(at: url)
        let features = try await FrameFeatureExtractor.extract(url: url)
        XCTAssertGreaterThan(features.count, 40)
        let peak = try XCTUnwrap(features.max { $0.histDiff < $1.histDiff })
        XCTAssertEqual(peak.t, 2.0, accuracy: 0.15)
        XCTAssertGreaterThan(peak.histDiff, 0.5)

        let input = AnalysisInput(features: features, audio: [], duration: 4)
        let s = HeuristicSuggester().suggest(input, sensitivity: 0.5)
        XCTAssertTrue(s.contains { $0.kind == .sceneCut && abs($0.time - 2.0) < 0.2 })
    }
}
