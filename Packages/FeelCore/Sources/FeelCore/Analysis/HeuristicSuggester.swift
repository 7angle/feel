// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Rule-based suggester. Robust z-scores keep thresholds relative to each video.
public struct HeuristicSuggester: HapticSuggester {
    public init() {}

    public func suggest(_ input: AnalysisInput, sensitivity: Double) -> [HapticSuggestion] {
        let f = input.features
        guard f.count > 6 else { return [] }
        let s = min(max(sensitivity, 0), 1)
        let k = 7.0 - 5.0 * s
        let dt = (f.last!.t - f[0].t) / Double(f.count - 1)
        guard dt > 0 else { return [] }

        let motion = f.map(\.motion)
        let mz = Self.zscores(motion, floor: 0.01)
        let hasAudio = input.audio.contains { $0 > 0.02 }
        let ae = f.map { Self.audioPeak(input.audio, around: $0.t, radius: dt / 2) }
        let az = Self.zscores(ae, floor: 0.02)
        func onset(_ i: Int) -> Bool {
            guard hasAudio, i >= 4 else { return false }
            let base = (ae[i - 4..<i].reduce(0, +)) / 4
            return az[i] > k * 0.8 && ae[i] - base > 0.15
        }
        func audioNear(_ i: Int, _ r: Int) -> Bool { (max(0, i - r)...min(f.count - 1, i + r)).contains(where: onset) }

        // Scene cuts.
        let cutThreshold = 0.55 - 0.3 * s
        var isCut = [Bool](repeating: false, count: f.count)
        for i in 1..<f.count where f[i].histDiff > cutThreshold { isCut[i] = true }
        func cutNear(_ i: Int) -> Bool { (max(0, i - 1)...min(f.count - 1, i + 1)).contains { isCut[$0] } }

        var out: [HapticSuggestion] = []

        // Explosions: bright flash plus motion or audio burst.
        var explosionTimes: [TimelineTime] = []
        for i in 2..<f.count {
            let jump = f[i].luma - f[i - 2].luma
            guard jump > 0.12, f[i].bright > 0.12, !isCut[i] || audioNear(i, 3) else { continue }
            guard mz[i] > k * 0.6 || audioNear(i, 3) else { continue }
            guard explosionTimes.last.map({ f[i].t - $0 > 1.0 }) ?? true else { continue }
            explosionTimes.append(f[i].t)
            let strength = min(1, 0.5 + f[i].bright)
            let events = (HapticPresetLibrary.preset(id: "explosion", custom: [])?.instantiate(at: f[i].t) ?? [])
            out.append(HapticSuggestion(kind: .explosion, time: f[i].t, duration: 1, strength: strength,
                                        reason: "Bright flash with a sudden burst of motion or sound.", events: events))
        }

        // Impacts: motion spike plus audio onset (or a very large spike when there is no audio).
        var impactTimes: [TimelineTime] = []
        for i in 4..<(f.count - 3) {
            guard mz[i] > k, motion[i] > 0.04, !cutNear(i) else { continue }
            // A jump, not a plateau of sustained motion.
            let before = motion[i - 4..<i].reduce(0, +) / 4
            guard motion[i] > 1.8 * before + 0.02 else { continue }
            guard (i - 2...i + 2).allSatisfy({ mz[$0] <= mz[i] }) else { continue }
            // Without audio, demand a true spike: motion must fall back, not stay high.
            let confirmed = hasAudio ? audioNear(i, 3) : (mz[i] > k * 1.3 && i + 3 < f.count && motion[i + 3] < 0.6 * motion[i])
            guard confirmed else { continue }
            guard !explosionTimes.contains(where: { abs($0 - f[i].t) < 0.5 }) else { continue }
            guard impactTimes.last.map({ f[i].t - $0 > 0.25 }) ?? true else { continue }
            let strength = min(1, max(0.3, mz[i] / (k * 2)))
            impactTimes.append(f[i].t)
            out.append(HapticSuggestion(
                kind: .impact, time: f[i].t, strength: strength,
                reason: hasAudio ? "Sudden motion with a sound hit." : "Sudden strong motion.",
                events: [HapticEvent(type: .tap, start: f[i].t, intensity: 0.5 + 0.5 * strength, sharpness: 0.8)]
            ))
        }

        // Scene cuts. Often not worth a vibration, so keep them modest.
        var lastCut = -10.0
        for i in 1..<f.count where isCut[i] {
            let t = f[i].t
            guard t - lastCut > 0.3 else { continue }
            lastCut = t
            guard !explosionTimes.contains(where: { abs($0 - t) < 0.3 }), !impactTimes.contains(where: { abs($0 - t) < 0.3 }) else { continue }
            let strength = min(1, f[i].histDiff)
            out.append(HapticSuggestion(kind: .sceneCut, time: t, strength: strength, reason: "Hard cut. Use only if it matters to the story.",
                                        events: [HapticEvent(type: .tap, start: t, intensity: 0.35 + 0.3 * strength, sharpness: 0.6)]))
        }

        // Sustained motion. High action also needs loud audio.
        let moving = (0..<f.count).map { mz[$0] > k * 0.5 && motion[$0] > 0.03 && !cutNear($0) }
        let loud = (0..<f.count).map { moving[$0] && hasAudio && az[$0] > k * 0.5 }
        let actionRuns = Self.runs(loud, minLen: Int(1.0 / dt), maxGap: Int(0.3 / dt))
        for r in actionRuns {
            let t0 = f[r.lowerBound].t, t1 = f[r.upperBound].t
            let dur = min(t1 - t0, 12)
            let curve = stride(from: 0.0, through: dur, by: 0.5).map { rel -> CurvePoint in
                let i = min(f.count - 1, max(0, Int((t0 + rel - f[0].t) / dt)))
                return CurvePoint(time: rel, value: min(1, max(0.35, 0.35 + ae[i])))
            }
            out.append(HapticSuggestion(
                kind: .highAction, time: t0, duration: dur, strength: min(1, 0.5 + (r.count > 0 ? Double(r.count) * dt / 10 : 0)),
                reason: "Sustained motion with loud audio.",
                events: [HapticEvent(type: .rumble, start: t0, duration: dur, intensity: 0.7, sharpness: 0.3, fadeIn: 0.2, fadeOut: 0.3, intensityCurve: curve)]
            ))
        }
        for r in Self.runs(moving, minLen: Int(0.6 / dt), maxGap: Int(0.25 / dt)) {
            let t0 = f[r.lowerBound].t, t1 = f[r.upperBound].t
            guard !actionRuns.contains(where: { $0.overlaps(r) }) else { continue }
            let dur = min(t1 - t0, 8)
            let meanZ = r.map { mz[$0] }.reduce(0, +) / Double(r.count)
            let strength = min(1, meanZ / (k * 2))
            out.append(HapticSuggestion(
                kind: .fastMovement, time: t0, duration: dur, strength: max(0.2, strength), reason: "Sustained fast movement.",
                events: [HapticEvent(type: .rumble, start: t0, duration: dur, intensity: 0.3 + 0.4 * min(1, strength * 1.5), sharpness: 0.4, fadeIn: 0.15, fadeOut: 0.25)]
            ))
        }

        // Camera shake: shift direction keeps reversing.
        let win = max(Int(0.6 / dt), 3)
        var shaking = [Bool](repeating: false, count: f.count)
        for i in 0..<f.count {
            let lo = max(0, i - win / 2), hi = min(f.count - 1, i + win / 2)
            var flips = 0, mag = 0.0
            var prev: Double?
            for j in lo...hi {
                let x = abs(f[j].shiftX) >= abs(f[j].shiftY) ? f[j].shiftX : f[j].shiftY
                mag += (f[j].shiftX * f[j].shiftX + f[j].shiftY * f[j].shiftY).squareRoot()
                if abs(x) >= 1 {
                    if let p = prev, p * x < 0 { flips += 1 }
                    prev = x
                }
            }
            shaking[i] = flips >= 3 && mag / Double(hi - lo + 1) >= 1 && !cutNear(i)
        }
        for r in Self.runs(shaking, minLen: Int(0.5 / dt), maxGap: Int(0.2 / dt)) {
            let t0 = f[r.lowerBound].t, dur = min(f[r.upperBound].t - t0, 8)
            out.append(HapticSuggestion(
                kind: .cameraShake, time: t0, duration: dur, strength: 0.6, reason: "Camera shakes back and forth.",
                events: [HapticEvent(type: .rumble, start: t0, duration: dur, intensity: 0.5, sharpness: 0.25, fadeIn: 0.1, fadeOut: 0.2)]
            ))
        }

        return out.sorted { $0.time < $1.time }
    }

    // MARK: Math

    /// Robust z-score: (x - median) / (1.4826 * MAD). `floor` avoids blowing up on static content.
    static func zscores(_ v: [Double], floor: Double) -> [Double] {
        let med = median(v)
        let mad = median(v.map { abs($0 - med) })
        let scale = max(1.4826 * mad, floor)
        return v.map { ($0 - med) / scale }
    }

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func audioPeak(_ audio: [Float], around t: TimelineTime, radius: TimelineTime) -> Double {
        guard !audio.isEmpty else { return 0 }
        let rate = AudioEnvelope.bucketsPerSecond
        let lo = max(0, Int((t - radius) * rate)), hi = min(audio.count - 1, Int((t + radius) * rate))
        guard lo <= hi else { return 0 }
        return Double(audio[lo...hi].max() ?? 0)
    }

    /// Index ranges where `mask` is true for at least `minLen` samples, bridging gaps up to `maxGap`.
    static func runs(_ mask: [Bool], minLen: Int, maxGap: Int) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var start: Int?, lastTrue = 0
        for i in 0..<mask.count {
            if mask[i] {
                if start == nil { start = i }
                lastTrue = i
            } else if let s = start, i - lastTrue > maxGap {
                if lastTrue - s + 1 >= minLen { out.append(s...lastTrue) }
                start = nil
            }
        }
        if let s = start, lastTrue - s + 1 >= minLen { out.append(s...lastTrue) }
        return out
    }
}
