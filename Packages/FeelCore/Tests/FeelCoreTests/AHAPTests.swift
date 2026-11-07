// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import XCTest
@testable import FeelCore

final class AHAPTests: XCTestCase {
    private func items(_ d: [String: Any]) -> [[String: Any]] { d["Pattern"] as? [[String: Any]] ?? [] }
    private func events(_ d: [String: Any]) -> [[String: Any]] { items(d).compactMap { $0["Event"] as? [String: Any] } }
    private func curves(_ d: [String: Any]) -> [[String: Any]] { items(d).compactMap { $0["ParameterCurve"] as? [String: Any] } }

    func testTapBecomesTransient() {
        let d = AHAPBuilder.pattern(events: [HapticEvent(type: .tap, start: 1.5, intensity: 0.4, sharpness: 0.9)])
        XCTAssertEqual(d["Version"] as? Double, 1.0)
        let e = events(d)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0]["EventType"] as? String, "HapticTransient")
        XCTAssertEqual(e[0]["Time"] as? Double, 1.5)
        let p = e[0]["EventParameters"] as? [[String: Any]]
        XCTAssertEqual(p?[0]["ParameterValue"] as? Double, 0.4)
        XCTAssertEqual(p?[1]["ParameterValue"] as? Double, 0.9)
    }

    func testTickTrainExpands() {
        let e = HapticEvent(type: .tickTrain, start: 1, repetitionInterval: 0.1, repetitionCount: 4)
        let times = events(AHAPBuilder.pattern(events: [e])).compactMap { $0["Time"] as? Double }
        XCTAssertEqual(times, [1.0, 1.1, 1.2, 1.3])
    }

    func testRumbleWithFadesAddsCurve() {
        let e = HapticEvent(type: .rumble, start: 0, duration: 2, fadeIn: 0.5, fadeOut: 0.5)
        let d = AHAPBuilder.pattern(events: [e])
        XCTAssertEqual(events(d).first?["EventDuration"] as? Double, 2)
        let c = curves(d)
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0]["ParameterID"] as? String, "HapticIntensityControl")
        let pts = c[0]["ParameterCurveControlPoints"] as? [[String: Any]]
        XCTAssertEqual(pts?.map { $0["Time"] as? Double }, [0, 0.5, 1.5, 2])
        XCTAssertEqual(pts?.map { $0["ParameterValue"] as? Double }, [0, 1, 1, 0])
    }

    func testPlainRumbleHasNoCurve() {
        let d = AHAPBuilder.pattern(events: [HapticEvent(type: .rumble, start: 0, duration: 1)])
        XCTAssertTrue(curves(d).isEmpty)
    }

    func testCurveCappedAt16Points() {
        let pts = (0..<40).map { CurvePoint(time: Double($0) * 0.05, value: Double($0 % 2)) }
        let e = HapticEvent(type: .rumble, start: 0, duration: 2, intensityCurve: pts)
        let c = curves(AHAPBuilder.pattern(events: [e]))
        XCTAssertLessThanOrEqual((c[0]["ParameterCurveControlPoints"] as? [Any])?.count ?? 99, 16)
    }

    /// (time, value) of all intensity control points, in pattern time.
    private func controlPoints(_ d: [String: Any]) -> [(t: Double, v: Double)] {
        curves(d).filter { $0["ParameterID"] as? String == "HapticIntensityControl" }.flatMap { c -> [(t: Double, v: Double)] in
            let t0 = c["Time"] as? Double ?? 0
            let pts = c["ParameterCurveControlPoints"] as? [[String: Any]] ?? []
            return pts.map { (t0 + ($0["Time"] as? Double ?? 0), $0["ParameterValue"] as? Double ?? 0) }
        }.sorted { $0.t < $1.t }
    }

    func testLongCurveChainsAndKeepsEveryPoint() {
        let pts = stride(from: 0.0, through: 12.0, by: 0.25).map { CurvePoint(time: $0, value: 0.5 + 0.5 * ($0 / 12)) }
        let e = HapticEvent(type: .rumble, start: 3, duration: 12, fadeIn: 0.15, fadeOut: 0.25, intensityCurve: pts)
        let c = curves(AHAPBuilder.pattern(events: [e]))
        XCTAssertGreaterThan(c.count, 2)
        for curve in c {
            XCTAssertLessThanOrEqual((curve["ParameterCurveControlPoints"] as? [Any])?.count ?? 99, 16)
        }
        let all = controlPoints(AHAPBuilder.pattern(events: [e]))
        // The fade-in stays short: full curve value at 0.15 s.
        let fade = all.first { abs($0.t - 3.15) < 1e-6 }
        XCTAssertEqual(fade?.v ?? 0, 0.5 + 0.5 * (0.15 / 12), accuracy: 0.02)
        XCTAssertEqual(all.first?.v ?? 9, 0, accuracy: 1e-6)
    }

    func testControlReturnsToNeutralAfterRumble() {
        let e = HapticEvent(type: .rumble, start: 1, duration: 2, fadeIn: 0.1, fadeOut: 0.5)
        let all = controlPoints(AHAPBuilder.pattern(events: [e]))
        XCTAssertEqual(all.last?.v, 1)
        XCTAssertEqual(all.last?.t ?? 0, 3.01, accuracy: 1e-6)
    }

    func testTapAfterRumbleIsNotChanged() {
        let rumble = HapticEvent(type: .rumble, start: 0, duration: 1, fadeOut: 0.25)
        let tap = HapticEvent(type: .tap, start: 2, intensity: 0.4)
        let t = events(AHAPBuilder.pattern(events: [rumble, tap])).first { $0["EventType"] as? String == "HapticTransient" }
        let p = t?["EventParameters"] as? [[String: Any]]
        XCTAssertEqual(p?[0]["ParameterValue"] as? Double, 0.4)
    }

    func testTapUnderRumbleCurveIsCompensatedInSinglePattern() {
        let rumble = HapticEvent(type: .rumble, start: 0, duration: 2,
                                 intensityCurve: [CurvePoint(time: 0, value: 0.5), CurvePoint(time: 2, value: 0.5)])
        let tap = HapticEvent(type: .tap, start: 1, intensity: 0.4)
        let t = events(AHAPBuilder.pattern(events: [rumble, tap])).first { $0["EventType"] as? String == "HapticTransient" }
        let p = t?["EventParameters"] as? [[String: Any]]
        XCTAssertEqual(p?[0]["ParameterValue"] as? Double ?? 0, 0.8, accuracy: 1e-6)
    }

    func testPatternsKeepTapsAwayFromCurves() {
        let a = HapticEvent(type: .rumble, start: 0, duration: 2, fadeOut: 0.5)
        let b = HapticEvent(type: .rumble, start: 1, duration: 2, fadeOut: 0.5)
        let c = HapticEvent(type: .rumble, start: 5, duration: 1, fadeOut: 0.5)
        let tap = HapticEvent(type: .tap, start: 1.5, intensity: 0.4)
        let list = AHAPBuilder.patterns(events: [a, b, c, tap])
        XCTAssertEqual(list.count, 3) // taps, then two rumble lanes
        XCTAssertTrue(curves(list[0]).isEmpty)
        XCTAssertEqual(events(list[0]).count, 1)
        let p = events(list[0])[0]["EventParameters"] as? [[String: Any]]
        XCTAssertEqual(p?[0]["ParameterValue"] as? Double, 0.4)
        XCTAssertEqual(events(list[1]).count, 2) // a and c do not overlap
        XCTAssertEqual(events(list[2]).count, 1)
    }

    func testPatternsOmitEmpty() {
        XCTAssertTrue(AHAPBuilder.patterns(events: []).isEmpty)
        XCTAssertEqual(AHAPBuilder.patterns(events: [HapticEvent(type: .rumble, start: 0, duration: 1)]).count, 1)
    }

    func testLongRumbleSplitsAt30s() {
        let e = HapticEvent(type: .rumble, start: 0, duration: 70)
        let ev = events(AHAPBuilder.pattern(events: [e]))
        XCTAssertEqual(ev.count, 3)
        XCTAssertTrue(ev.allSatisfy { ($0["EventDuration"] as? Double ?? 99) <= 30 })
        XCTAssertEqual(ev.compactMap { $0["EventDuration"] as? Double }.reduce(0, +), 70, accuracy: 1e-6)
    }

    func testWindowShiftsAndTrims() {
        let tap = HapticEvent(type: .tap, start: 5)
        let early = HapticEvent(type: .tap, start: 1)
        let rumble = HapticEvent(type: .rumble, start: 4, duration: 4)
        let ev = events(AHAPBuilder.pattern(events: [tap, early, rumble], from: 6, to: 20))
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev[0]["Time"] as? Double, 0)
        XCTAssertEqual(ev[0]["EventDuration"] as? Double, 2)
    }

    func testSharpnessCurveIsAdditiveOffset() {
        let e = HapticEvent(type: .rumble, start: 0, duration: 1, sharpness: 0.8,
                            sharpnessCurve: [CurvePoint(time: 0, value: 1), CurvePoint(time: 1, value: 0.5)])
        let c = curves(AHAPBuilder.pattern(events: [e]))
        XCTAssertEqual(c[0]["ParameterID"] as? String, "HapticSharpnessControl")
        let v = (c[0]["ParameterCurveControlPoints"] as? [[String: Any]])?.compactMap { $0["ParameterValue"] as? Double }
        XCTAssertEqual(v?.first ?? 9, 0, accuracy: 1e-6)
        XCTAssertEqual(v?.last ?? 9, -0.4, accuracy: 1e-6)
    }

    func testDataIsValidJSON() throws {
        let data = try AHAPBuilder.data(events: HapticPresetLibrary.builtIn.flatMap { $0.instantiate(at: 1) })
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["Pattern"])
    }

    func testEveryBuiltInPresetProducesEvents() {
        for p in HapticPresetLibrary.builtIn {
            XCTAssertFalse(events(AHAPBuilder.pattern(events: p.events)).isEmpty, p.name)
        }
    }
}
