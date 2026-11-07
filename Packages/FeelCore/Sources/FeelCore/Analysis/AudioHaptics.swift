// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Builds haptic events from the audio spectrum.
public enum AudioHaptics {
    /// Marks events that this generator made and the user did not edit.
    public static let generatorID = "audio"

    /// Bass swells become rumbles. Hits found by spectral change become taps.
    /// Bass-heavy hits feel soft and heavy. Bright hits feel sharp.
    /// Speech makes no rumbles and no taps, except a loud bass hit under it.
    public static func generate(spectrum sp: AudioSpectrum, sensitivity: Double) -> [HapticEvent] {
        let rate = AudioSpectrum.rate
        let n = sp.count
        guard n > Int(rate), sp.mid.count == n, sp.high.count == n else { return [] }
        let s = min(max(sensitivity, 0), 1)
        let duration = Double(n) / rate

        func norm(_ v: [Float], pct: Double, floor: Double) -> [Double] {
            let sorted = v.sorted()
            let top = max(Double(sorted[min(n - 1, Int(Double(n) * pct))]), floor)
            return v.map { min(Double($0) / top, 1.5) }
        }
        let bass = smooth(norm(sp.bass, pct: 0.995, floor: 0.02), radius: 2)
        let mid = smooth(norm(sp.mid, pct: 0.995, floor: 0.02), radius: 2)
        let high = smooth(norm(sp.high, pct: 0.995, floor: 0.02), radius: 2)
        let fb = norm(sp.fluxBass, pct: 0.99, floor: 0.01)
        let fm = norm(sp.fluxMid, pct: 0.99, floor: 0.01)
        let fh = norm(sp.fluxHigh, pct: 0.99, floor: 0.01)
        guard (bass + mid + high).contains(where: { $0 > 0.05 }) else { return [] }

        var out: [HapticEvent] = []

        // Rumbles follow the bass. Loud is relative to the surrounding ~10 s.
        let slow = smooth(bass, radius: Int(0.15 * rate))
        let local = smooth(bass, radius: Int(5 * rate))
        let swell = 1.45 - 0.3 * s
        let speaking = speechMask(sp.speech, count: n)
        let mask = rumbleMask(slow: slow, enter: slow.indices.map { !speaking[$0] && slow[$0] > 0.3 && slow[$0] > local[$0] * swell })
        for r in runs(mask, minLen: Int(0.8 * rate), maxGap: Int(0.3 * rate)) {
            let t0 = Double(r.lowerBound) / rate
            let dur = Double(r.count) / rate
            let curve = stride(from: 0.0, through: dur, by: 0.25).map { rel -> CurvePoint in
                CurvePoint(time: rel, value: min(1, max(0.3, slow[min(n - 1, r.lowerBound + Int(rel * rate))])))
            }
            out.append(HapticEvent(
                type: .rumble, start: t0, duration: dur, intensity: 0.8, sharpness: 0.2,
                fadeIn: min(0.15, dur / 4), fadeOut: min(0.25, dur / 4), intensityCurve: curve
            ))
        }

        // Onsets: spectral change across all bands, bass weighted most.
        let flux = smooth((0..<n).map { 1.0 * fb[$0] + 0.6 * fm[$0] + 0.9 * fh[$0] }, radius: 1)
        // Adaptive threshold: local mean over +-0.5 s, plus a margin from the global spread.
        // Quiet passages keep their hits. Busy passages do not flood.
        let around = smooth(flux, radius: Int(0.5 * rate))
        let mean = flux.reduce(0, +) / Double(n)
        let spread = (flux.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)).squareRoot()
        let k = 2.0 - 0.8 * s
        let delta = spread * (0.9 - 0.7 * s)
        let radius = max(1, Int(0.05 * rate))
        var candidates: [(i: Int, strength: Double)] = []
        for i in radius..<(n - radius) {
            let f = flux[i]
            guard f > around[i] * k + delta else { continue }
            guard (i - radius...i + radius).allSatisfy({ flux[$0] <= f }) else { continue }
            candidates.append((i, f))
        }
        // Spacing is the only density rule. The cap is a safety limit, not a target.
        let maxCount = max(1, Int(duration * (4 + 8 * s)))
        let spacing = Int(0.10 * rate)
        var kept: [(i: Int, strength: Double)] = []
        for c in candidates.sorted(by: { $0.strength > $1.strength }) {
            guard kept.count < maxCount else { break }
            guard !kept.contains(where: { abs($0.i - c.i) < spacing }) else { continue }
            kept.append(c)
        }
        let latency = 0.02 // window centre sits after the hop start

        struct Feel { var i: Int; var level: Double; var brightness: Double; var bassShare: Double }
        let feels = kept.map { c -> Feel in
            let lo = max(0, c.i - 2), hi = min(n - 1, c.i + 2)
            let b = fb[lo...hi].reduce(0, +), m = fm[lo...hi].reduce(0, +), h = fh[lo...hi].reduce(0, +)
            let total = max(b + m + h, 1e-6)
            // Loudest band just after the hit. The energy arrives over the next frames.
            let end = min(n - 1, c.i + 5)
            let level = (c.i...end).reduce(0.0) { max($0, bass[$1], mid[$1], high[$1]) }
            return Feel(i: c.i, level: min(level, 1), brightness: (h + 0.5 * m) / total, bassShare: b / total)
        }.filter { !speaking[$0.i] || ($0.bassShare > 0.5 && $0.level > 0.7) }
        // Spread sharpness across the clip. Loud music would otherwise put every tap at the top.
        func ranks(_ v: [Double]) -> [Double] {
            guard v.count > 1 else { return v.map { _ in 0.5 } }
            let order = v.indices.sorted { v[$0] < v[$1] }
            var r = [Double](repeating: 0, count: v.count)
            for (pos, idx) in order.enumerated() { r[idx] = Double(pos) / Double(v.count - 1) }
            return r
        }
        let brightRank = ranks(feels.map(\.brightness))
        for (k, f) in feels.enumerated() {
            // Loud hits feel strong and quiet hits feel weaker. Weak or dull transients
            // are not felt on an iPhone, so both values have a floor.
            let intensity = 0.5 + 0.5 * f.level
            var sharpness = 0.5 + 0.5 * brightRank[k]
            if f.bassShare > 0.5 { sharpness = min(sharpness, 0.6) }
            out.append(HapticEvent(type: .tap, start: Double(f.i) / rate + latency, intensity: intensity, sharpness: sharpness))
        }

        return out.sorted { $0.start < $1.start }.map { e in
            var n = e
            n.generatedBy = generatorID
            return n
        }
    }

    // MARK: Math

    static func speechMask(_ ranges: [ClosedRange<Double>], count: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: count)
        for r in ranges {
            let lo = max(0, Int(r.lowerBound * AudioSpectrum.rate))
            let hi = min(count - 1, Int(r.upperBound * AudioSpectrum.rate))
            if lo <= hi { for i in lo...hi { mask[i] = true } }
        }
        return mask
    }

    /// The swell test only starts a rumble. The local average catches up during a long passage,
    /// so the rumble then holds while the level stays near its peak, up to the Core Haptics
    /// limit for one continuous event.
    static func rumbleMask(slow: [Double], enter: [Bool]) -> [Bool] {
        let maxLen = Int(AHAPBuilder.maxContinuousDuration * AudioSpectrum.rate)
        var mask = [Bool](repeating: false, count: slow.count)
        var start: Int?
        var peak = 0.0
        for i in slow.indices {
            if let st = start {
                peak = max(peak, slow[i])
                if slow[i] < 0.3 || slow[i] < peak * 0.6 || i - st >= maxLen { start = nil }
            } else if enter[i] {
                start = i
                peak = slow[i]
            }
            mask[i] = start != nil
        }
        return mask
    }

    static func smooth(_ v: [Double], radius: Int) -> [Double] {
        guard radius > 0, !v.isEmpty else { return v }
        var prefix = [Double](repeating: 0, count: v.count + 1)
        for i in v.indices { prefix[i + 1] = prefix[i] + v[i] }
        return v.indices.map { i in
            let lo = max(0, i - radius), hi = min(v.count - 1, i + radius)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }

    static func runs(_ mask: [Bool], minLen: Int, maxGap: Int) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var start: Int?, lastTrue = 0
        for i in 0..<mask.count {
            if mask[i] {
                if start == nil { start = i }
                lastTrue = i
            } else if let st = start, i - lastTrue > maxGap {
                if lastTrue - st + 1 >= minLen { out.append(st...lastTrue) }
                start = nil
            }
        }
        if let st = start, lastTrue - st + 1 >= minLen { out.append(st...lastTrue) }
        return out
    }
}
