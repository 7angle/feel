// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class AutoHapticsTests: XCTestCase {
    private let sr = SpectrumAnalyzer.sampleRate

    /// 20 s of still picture with small noise, at the rate of the real extractor.
    private func stillFeatures() -> [FrameFeature] {
        (0..<300).map { i in
            FrameFeature(t: Double(i) / 15, motion: 0.002 + 0.001 * Double(i % 3))
        }
    }

    /// Quiet hum plus short clicks at the given times.
    private func spectrum(clicks: [Double]) -> AudioSpectrum {
        var s = [Float](repeating: 0, count: Int(20 * sr))
        for i in s.indices { s[i] = 0.05 * Float(sin(2 * .pi * 440 * Double(i) / sr)) }
        for click in clicks {
            for i in Int(click * sr)..<Int((click + 0.05) * sr) {
                s[i] += 0.7 * Float(sin(2 * .pi * 4000 * Double(i) / sr))
            }
        }
        return SpectrumAnalyzer.analyze(s)
    }

    private func input(_ features: [FrameFeature]) -> AnalysisInput {
        AnalysisInput(features: features, audio: [], duration: 20)
    }

    func testBusyAudioOnAStillPictureIsThinned() {
        let sp = spectrum(clicks: stride(from: 1.0, to: 19.0, by: 0.2).map { $0 })
        let audioOnly = AudioHaptics.generate(spectrum: sp, sensitivity: 0.5).filter { $0.type == .tap }
        let taps = AutoHaptics.generate(spectrum: sp, input: input(stillFeatures()), sensitivity: 0.5).filter { $0.type == .tap }
        XCTAssertGreaterThan(audioOnly.count, 60)
        XCTAssertGreaterThan(taps.count, 10)
        XCTAssertLessThan(taps.count, 25)
        XCTAssertTrue(taps.allSatisfy { $0.intensity <= AutoHaptics.audioOnlyScale })
    }

    func testHitWithMotionIsStrongerThanHitWithout() throws {
        var f = stillFeatures()
        f[60].motion = 0.2 // 4 s
        let sp = spectrum(clicks: [4.0, 10.0])
        let taps = AutoHaptics.generate(spectrum: sp, input: input(f), sensitivity: 0.5).filter { $0.type == .tap }
        let seen = try XCTUnwrap(taps.first { abs($0.start - 4) < 0.15 })
        let heard = try XCTUnwrap(taps.first { abs($0.start - 10) < 0.15 })
        XCTAssertGreaterThan(seen.intensity, heard.intensity)
    }

    func testImpactSnapsToAudioHit() throws {
        var f = stillFeatures()
        f[90].motion = 0.3 // 6 s
        let hit = 6.07
        let sp = spectrum(clicks: [hit])
        let audio = try XCTUnwrap(AudioHaptics.generate(spectrum: sp, sensitivity: 0.5).first { abs($0.start - hit) < 0.1 })
        let near = AutoHaptics.generate(spectrum: sp, input: input(f), sensitivity: 0.5)
            .filter { $0.type == .tap && abs($0.start - hit) < 0.3 }
        XCTAssertEqual(near.count, 1)
        XCTAssertEqual(near.first?.start ?? 0, audio.start, accuracy: 1e-9)
    }

    func testFastMovementRumbleNeedsNoBass() {
        var f = stillFeatures()
        for i in 60..<105 { f[i].motion = 0.1 } // 3 s of movement
        let sp = spectrum(clicks: [15])
        let rumbles = AutoHaptics.generate(spectrum: sp, input: input(f), sensitivity: 0.5).filter { $0.type == .rumble }
        XCTAssertEqual(rumbles.count, 1)
        XCTAssertEqual(rumbles.first?.start ?? 0, 4, accuracy: 0.3)
    }

    func testAllEventsAreMarkedAndIdsAreUnique() {
        var f = stillFeatures()
        f[60].motion = 0.2
        let e = AutoHaptics.generate(spectrum: spectrum(clicks: [4, 10]), input: input(f), sensitivity: 0.5)
        XCTAssertFalse(e.isEmpty)
        XCTAssertTrue(e.allSatisfy { $0.generatedBy == AudioHaptics.generatorID })
        XCTAssertEqual(Set(e.map(\.id)).count, e.count)
    }

    func testNoFeaturesStillUsesAudio() {
        let e = AutoHaptics.generate(spectrum: spectrum(clicks: [4]), input: input([]), sensitivity: 0.5)
        XCTAssertFalse(e.isEmpty)
    }
}
