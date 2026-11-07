// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import CoreHaptics
import FeelCore
import Foundation

/// Wraps CHHapticEngine. Handles interruptions, resets, and scheduled playback windows.
@MainActor
final class HapticPlayer {
    private var engine: CHHapticEngine?
    /// The scheduled window. Kept until the next window replaces it.
    private var players: [CHHapticPatternPlayer] = []
    private var auditions: [CHHapticPatternPlayer] = []
    private(set) var isReady = false
    var onReadyChange: ((Bool, String?) -> Void)?
    /// Called after engine restarts so caller can reschedule.
    var onRestart: (() -> Void)?
    /// Short status for the screen: stops, restarts, items scheduled, errors.
    var onDebug: ((String) -> Void)?
    private var stops = 0, restarts = 0, errors = 0, lastItems = 0, lastStop = "-"

    private func report() {
        onDebug?("scheduled \(lastItems) · stops \(stops) (\(lastStop)) · restarts \(restarts) · errors \(errors)")
    }

    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare() {
        guard supportsHaptics else { onReadyChange?(false, "This device does not support Core Haptics."); return }
        guard engine == nil else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = false
            e.playsHapticsOnly = true
            e.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    guard let self else { return }
                    self.stops += 1
                    self.lastStop = "\(reason.rawValue)"
                    self.report()
                    self.isReady = false
                    // Video or sound can take the audio session and stop the engine. Start again at once,
                    // then the caller reschedules the lost haptics.
                    if reason != .applicationSuspended, self.engine != nil {
                        self.restart()
                    } else {
                        self.onReadyChange?(false, "Haptic engine stopped (\(reason.rawValue)).")
                    }
                }
            }
            e.resetHandler = { [weak self] in
                Task { @MainActor in self?.restart() }
            }
            engine = e
            try e.start()
            isReady = true
            onReadyChange?(true, nil)
        } catch {
            engine = nil
            isReady = false
            onReadyChange?(false, "Haptic engine failed: \(error.localizedDescription)")
        }
    }

    /// Engine reset or stopped by system. Start again, then ask caller to reschedule.
    func restart() {
        guard engine != nil else { return prepare() }
        if startEngine() { onRestart?() }
    }

    /// Does not call `onRestart`. `play` uses this, because a reschedule inside `play` would play every haptic twice.
    private func startEngine() -> Bool {
        guard let engine else {
            prepare()
            return isReady
        }
        do {
            try engine.start()
            isReady = true
            restarts += 1
            report()
            onReadyChange?(true, nil)
            return true
        } catch {
            self.engine = nil
            isReady = false
            onReadyChange?(false, "Cannot restart haptics: \(error.localizedDescription)")
            return false
        }
    }

    func stopAll() {
        for p in players + auditions { try? p.stop(atTime: CHHapticTimeImmediate) }
        players.removeAll()
        auditions.removeAll()
    }

    /// Play one event now.
    func audition(_ event: HapticEvent) {
        var e = event
        e.start = 0
        play(events: [e], delay: 0, replacing: false)
    }

    /// Schedule events in timeline window [from, to). Pattern time 0 = `from`. Starts after `delay` seconds.
    func play(events: [HapticEvent], from: TimelineTime = 0, to: TimelineTime? = nil, delay: TimeInterval, replacing: Bool = true) {
        if replacing { stopAll() }
        if !isReady { _ = startEngine() }
        guard let engine, isReady else { return }
        // Fixed before the build, so build time does not make the haptics late.
        let at = delay <= 0 ? CHHapticTimeImmediate : engine.currentTime + delay
        do {
            var items = 0
            for var dict in AHAPBuilder.patterns(events: events, from: from, to: to) {
                dict.removeValue(forKey: "Metadata")
                items += (dict["Pattern"] as? [Any])?.count ?? 0
                let pattern = try CHHapticPattern(dictionary: Self.convert(dict) as? [CHHapticPattern.Key: Any] ?? [:])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: at)
                if replacing {
                    players.append(player)
                } else {
                    auditions.append(player)
                    if auditions.count > 8 { auditions.removeFirst(auditions.count - 8) }
                }
            }
            lastItems = items
            report()
        } catch {
            errors += 1
            report()
            onReadyChange?(isReady, "Playback error: \(error.localizedDescription)")
        }
    }

    /// JSON-style dictionaries use plain string keys. Core Haptics wants CHHapticPattern.Key.
    private static func convert(_ value: Any) -> Any {
        if let d = value as? [String: Any] {
            var out: [CHHapticPattern.Key: Any] = [:]
            for (k, v) in d { out[CHHapticPattern.Key(rawValue: k)] = convert(v) }
            return out
        }
        if let a = value as? [Any] { return a.map(convert) }
        return value
    }
}
