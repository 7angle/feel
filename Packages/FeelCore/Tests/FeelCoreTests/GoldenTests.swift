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
