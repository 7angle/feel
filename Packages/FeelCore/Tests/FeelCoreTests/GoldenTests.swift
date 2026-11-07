// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

/// Writes the files the Android tests compare against, so both ports stay the same.
/// Run: FEEL_GOLDEN_DIR=Apps/FeelAndroid/app/src/test/resources swift test --filter GoldenTests
/// The Android test `AudioGoldenTest` builds the same signal.
final class GoldenTests: XCTestCase {
    private struct Bands: Codable {
        var stride: Int
        var count: Int
        var bass: [Float]
        var mid: [Float]
        var high: [Float]
        var fluxBass: [Float]
        var fluxMid: [Float]
        var fluxHigh: [Float]
    }

    private struct Run: Codable {
        var sensitivity: Double
        var speech: [[Double]]
        var events: [HapticEvent]
    }

    private struct Golden: Codable {
        var bands: Bands
        var runs: [Run]
    }

    /// Hum, noise, regular bass hits, regular clicks, and one long bass swell. 30 s at 16 kHz.
    static func signal() -> [Float] {
        let sr = SpectrumAnalyzer.sampleRate
        var s = [Float](repeating: 0, count: Int(30 * sr))
        var x: UInt32 = 12345
        for i in s.indices {
            x = x &* 1_664_525 &+ 1_013_904_223
            s[i] = (Float((x >> 16) & 0x7fff) / 16384 - 1) * 0.02
        }
        func sine(_ f: Double, _ amp: Float, _ a: Double, _ b: Double) {
            for i in Int(a * sr)..<Int(b * sr) { s[i] += amp * Float(sin(2 * .pi * f * Double(i) / sr)) }
        }
        sine(440, 0.1, 0, 30)
        var t = 1.0
        while t < 29 { sine(70, 0.6, t, t + 0.1); t += 1 }
        t = 2.0
        while t < 29 { sine(4000, 0.5, t, t + 0.03); t += 1.37 }
        sine(60, 0.7, 15, 22)
        return s
    }

    private struct Feature: Codable {
        var t, luma, histDiff, motion, shiftX, shiftY, bright: Double
    }

    private struct AutoRun: Codable {
        var sensitivity: Double
        var events: [HapticEvent]
    }

    private struct AutoGolden: Codable {
        var features: [Feature]
        var audio: [Float]
        var runs: [AutoRun]
    }

    /// 30 s at 15 samples per second, with one of each moment the suggester knows.
    static func autoFeatures() -> [FrameFeature] {
        var f = (0..<450).map { i in
            FrameFeature(t: Double(i) / 15, luma: 0.35, histDiff: 0.01, motion: 0.01 + 0.002 * Double(i % 3))
        }
        f[75].motion = 0.2 // impact, on the bass hit at 5 s
        f[120].histDiff = 0.9 // scene cut at 8 s
        f[120].motion = 0.25
        for i in 150..<188 { f[i].motion = 0.1 } // fast movement
        for i in 255..<285 { // camera shake
            f[i].shiftX = i % 2 == 0 ? 3 : -3
            f[i].motion = 0.015
        }
        for i in 300..<330 { f[i].motion = 0.1 } // high action, in the bass swell
        for i in 375..<379 { // explosion
            f[i].luma = 0.8
            f[i].bright = 0.4
            f[i].motion = 0.3
        }
        return f
    }

    /// Run: FEEL_GOLDEN_DIR=Apps/FeelAndroid/app/src/test/resources swift test --filter GoldenTests/testWriteAutoGolden
    func testWriteAutoGolden() throws {
        let signal = Self.signal()
        let hop = Int(SpectrumAnalyzer.sampleRate / AudioEnvelope.bucketsPerSecond)
        let audio = stride(from: 0, to: signal.count - hop + 1, by: hop).map { start in
            signal[start..<start + hop].reduce(Float(0)) { max($0, abs($1)) }
        }
        let features = Self.autoFeatures()
        let input = AnalysisInput(features: features, audio: audio, duration: 30)
        let kinds = Set(HeuristicSuggester().suggest(input, sensitivity: 0.5).map(\.kind))
        XCTAssertEqual(kinds, Set(SuggestionKind.allCases))
        guard let dir = ProcessInfo.processInfo.environment["FEEL_GOLDEN_DIR"] else {
            throw XCTSkip("Set FEEL_GOLDEN_DIR to write the Android golden files.")
        }
        let sp = SpectrumAnalyzer.analyze(signal)
        let golden = AutoGolden(
            features: features.map { Feature(t: $0.t, luma: $0.luma, histDiff: $0.histDiff, motion: $0.motion, shiftX: $0.shiftX, shiftY: $0.shiftY, bright: $0.bright) },
            audio: audio,
            runs: [0.0, 0.5, 1.0].map { AutoRun(sensitivity: $0, events: AutoHaptics.generate(spectrum: sp, input: input, sensitivity: $0)) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(golden).write(to: URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("auto-golden.json"))
    }

    func testWriteGolden() throws {
        guard let dir = ProcessInfo.processInfo.environment["FEEL_GOLDEN_DIR"] else {
            throw XCTSkip("Set FEEL_GOLDEN_DIR to write the Android golden files.")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        let sp = SpectrumAnalyzer.analyze(Self.signal())
        let step = 37
        func picked(_ v: [Float]) -> [Float] { stride(from: 0, to: v.count, by: step).map { v[$0] } }
        let bands = Bands(
            stride: step, count: sp.count, bass: picked(sp.bass), mid: picked(sp.mid), high: picked(sp.high),
            fluxBass: picked(sp.fluxBass), fluxMid: picked(sp.fluxMid), fluxHigh: picked(sp.fluxHigh)
        )
        var runs: [Run] = []
        for s in [0.0, 0.5, 1.0] {
            runs.append(Run(sensitivity: s, speech: [], events: AudioHaptics.generate(spectrum: sp, sensitivity: s)))
        }
        var spoken = sp
        spoken.speech = [5.0...9.0]
        runs.append(Run(sensitivity: 0.5, speech: [[5, 9]], events: AudioHaptics.generate(spectrum: spoken, sensitivity: 0.5)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Golden(bands: bands, runs: runs)).write(to: folder.appendingPathComponent("audio-golden.json"))

        var p = HapticProject(name: "Clip")
        p.video = VideoReference(url: URL(fileURLWithPath: "/v/clip.mp4"), bookmark: nil,
                                 metadata: VideoMetadata(duration: 20, frameRate: 24, width: 1920, height: 1080))
        p.events = HapticPresetLibrary.preset(id: "explosion", custom: [])!.instantiate(at: 8)
            + HapticPresetLibrary.preset(id: "heartbeat", custom: [])!.instantiate(at: 2)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try ExportEngine.json(p, now: date).write(to: folder.appendingPathComponent("share-golden.json"))
    }
}
