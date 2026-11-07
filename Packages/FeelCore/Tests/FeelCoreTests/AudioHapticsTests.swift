// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class AudioHapticsTests: XCTestCase {
    func testResizeRumbleStartKeepsEnd() {
        let e = HapticEvent(type: .rumble, start: 2, duration: 2, intensityCurve: [CurvePoint(time: 0, value: 1), CurvePoint(time: 2, value: 0.5)])
        let r = EventEditing.resized(e, edge: .start, to: 1, grid: nil, limit: 0)
        XCTAssertEqual(r.start, 1, accuracy: 1e-9)
        XCTAssertEqual(r.end, 4, accuracy: 1e-9)
        XCTAssertEqual(r.intensityCurve.last?.time ?? 0, 3, accuracy: 1e-9)
    }

    func testResizeRumbleStartCannotPassEnd() {
        let e = HapticEvent(type: .rumble, start: 2, duration: 1)
        let r = EventEditing.resized(e, edge: .start, to: 9, grid: nil, limit: 0)
        XCTAssertEqual(r.duration, 0.05, accuracy: 1e-9)
    }

    func testResizeTickTrainChangesCount() {
        let e = HapticEvent(type: .tickTrain, start: 1, repetitionInterval: 0.1, repetitionCount: 4)
        let r = EventEditing.resized(e, edge: .end, to: 2.05, grid: nil, limit: 0)
        XCTAssertEqual(r.repetitionCount, 11)
        let tiny = EventEditing.resized(e, edge: .end, to: 0, grid: nil, limit: 0)
        XCTAssertEqual(tiny.repetitionCount, 1)
    }
}

final class VideoMessageTests: XCTestCase {
    func testChunkRoundTrip() throws {
        let m = Message.videoChunk(id: "a", offset: 5, data: Data([1, 2, 3, 0x0A]))
        let line = try m.encoded()
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1) // only the terminator
        XCTAssertEqual(try Message.decode(line.dropLast()), m)
    }
}

final class SpectralTests: XCTestCase {
    private let sr = SpectrumAnalyzer.sampleRate

    private func sine(_ f: Double, _ amp: Float, from a: Double, to b: Double, into s: inout [Float]) {
        for i in Int(a * sr)..<Int(b * sr) { s[i] += amp * Float(sin(2 * .pi * f * Double(i) / sr)) }
    }

    /// Steady hum plus two bursts: 80 Hz thump at 3 s, 4 kHz click at 6 s.
    private func signal() -> [Float] {
        var s = [Float](repeating: 0, count: Int(10 * sr))
        sine(440, 0.2, from: 0, to: 10, into: &s)
        sine(80, 0.7, from: 3.0, to: 3.15, into: &s)
        sine(4000, 0.7, from: 6.0, to: 6.05, into: &s)
        return s
    }

    func testBandsSeparate() {
        let sp = SpectrumAnalyzer.analyze(signal())
        XCTAssertEqual(sp.count, 1000 - 2, accuracy: 4)
        XCTAssertGreaterThan(sp.bass[305], sp.bass[100] * 2)
        XCTAssertGreaterThan(sp.high[602], sp.high[100] * 2)
    }

    func testBassHitIsSoftAndHighClickIsSharp() {
        let e = AudioHaptics.generate(spectrum: SpectrumAnalyzer.analyze(signal()), sensitivity: 0.7).filter { $0.type == .tap }
        let thump = e.first { abs($0.start - 3.0) < 0.2 }
        let click = e.first { abs($0.start - 6.0) < 0.2 }
        XCTAssertNotNil(thump)
        XCTAssertNotNil(click)
        XCTAssertLessThan(thump?.sharpness ?? 1, click?.sharpness ?? 0)
    }

    func testLongBassPassageHasOneUnbrokenRumble() {
        var s = [Float](repeating: 0, count: Int(45 * sr))
        sine(440, 0.1, from: 0, to: 45, into: &s)
        sine(60, 0.7, from: 10, to: 35, into: &s)
        let r = AudioHaptics.generate(spectrum: SpectrumAnalyzer.analyze(s), sensitivity: 0.5).filter { $0.type == .rumble }
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.start ?? 0, 10, accuracy: 0.3)
        XCTAssertEqual(r.first?.end ?? 0, 35, accuracy: 0.5)
    }

    func testLouderHitsAreStronger() {
        var s = [Float](repeating: 0, count: Int(20 * sr))
        var t = 1.0
        while t < 10 { sine(70, 0.8, from: t, to: t + 0.08, into: &s); t += 0.5 }
        while t < 19 { sine(70, 0.03, from: t, to: t + 0.08, into: &s); t += 0.5 }
        let e = AudioHaptics.generate(spectrum: SpectrumAnalyzer.analyze(s), sensitivity: 0.5).filter { $0.type == .tap }
        let loud = e.filter { $0.start < 10 }.map(\.intensity)
        let quiet = e.filter { $0.start >= 10 }.map(\.intensity)
        XCTAssertFalse(loud.isEmpty)
        XCTAssertFalse(quiet.isEmpty)
        XCTAssertGreaterThan(loud.reduce(0, +) / Double(loud.count), quiet.reduce(0, +) / Double(quiet.count) + 0.2)
        XCTAssertGreaterThanOrEqual(quiet.min() ?? 0, 0.5)
    }

    func testSilenceYieldsNothing() {
        let sp = SpectrumAnalyzer.analyze([Float](repeating: 0, count: Int(5 * sr)))
        XCTAssertTrue(AudioHaptics.generate(spectrum: sp, sensitivity: 0.5).isEmpty)
    }

    func testHigherSensitivityFindsAtLeastAsMany() {
        let sp = SpectrumAnalyzer.analyze(signal())
        let lo = AudioHaptics.generate(spectrum: sp, sensitivity: 0).count
        let hi = AudioHaptics.generate(spectrum: sp, sensitivity: 1).count
        XCTAssertGreaterThanOrEqual(hi, lo)
    }

    func testSpeechRemovesBrightHitAndKeepsLoudBassHit() {
        var sp = SpectrumAnalyzer.analyze(signal())
        sp.speech = [2.5...7.0]
        let e = AudioHaptics.generate(spectrum: sp, sensitivity: 0.7).filter { $0.type == .tap }
        XCTAssertNotNil(e.first { abs($0.start - 3.0) < 0.2 })
        XCTAssertNil(e.first { abs($0.start - 6.0) < 0.2 })
    }

    func testSpeechStopsRumbleStart() {
        var s = [Float](repeating: 0, count: Int(30 * sr))
        sine(440, 0.1, from: 0, to: 30, into: &s)
        sine(60, 0.7, from: 10, to: 16, into: &s)
        var sp = SpectrumAnalyzer.analyze(s)
        sp.speech = [9.0...17.0]
        XCTAssertTrue(AudioHaptics.generate(spectrum: sp, sensitivity: 0.5).filter { $0.type == .rumble }.isEmpty)
    }

    func testSpeechRangesMergeAndTrim() {
        XCTAssertEqual(SpeechDetector.merged([2.0...3.0, 0.0...1.0, 0.5...1.5, 5.0...5.3], trim: 0.2), [0.2...1.3, 2.2...2.8])
    }

    func testEventsAreMarkedAndEditsClearTheMark() {
        let e = AudioHaptics.generate(spectrum: SpectrumAnalyzer.analyze(signal()), sensitivity: 0.7)
        XCTAssertFalse(e.isEmpty)
        XCTAssertTrue(e.allSatisfy { $0.generatedBy == AudioHaptics.generatorID })
        var moved = e
        EventEditing.move(&moved, origins: [e[0].id: e[0].start], delta: 0.1, anchor: nil, grid: nil, duration: 0)
        XCTAssertNil(moved[0].generatedBy)
        XCTAssertEqual(moved[1].generatedBy, AudioHaptics.generatorID)
        XCTAssertNil(EventEditing.duplicate(e)[0].generatedBy)
    }

    func testOldProjectEventsDecodeWithoutMark() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","type":"tap","start":1,"duration":0,"intensity":1,"sharpness":1,"repetitionInterval":0.1,"repetitionCount":1,"fadeIn":0,"fadeOut":0,"intensityCurve":[],"sharpnessCurve":[]}"#
        XCTAssertNil(try JSONDecoder().decode(HapticEvent.self, from: Data(json.utf8)).generatedBy)
    }

    func testSteadyToneGivesNoTaps() {
        var s = [Float](repeating: 0, count: Int(8 * sr))
        sine(440, 0.5, from: 0, to: 8, into: &s)
        let e = AudioHaptics.generate(spectrum: SpectrumAnalyzer.analyze(s), sensitivity: 0.7)
        XCTAssertTrue(e.filter { $0.type == .tap }.isEmpty)
    }
}
