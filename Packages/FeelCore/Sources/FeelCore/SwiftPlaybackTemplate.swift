// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

/// Source of the generated integration file. Must compile on iOS 16+.
public enum SwiftPlaybackTemplate {
    public static func source(ahapName: String) -> String {
        template.replacingOccurrences(of: "__AHAP_NAME__", with: ahapName)
    }

    private static let template = #"""
import AVFoundation
import CoreHaptics
import Foundation

/// Plays "__AHAP_NAME__.ahap" in step with an AVPlayer.
///
/// Usage:
///
///     let player = AVPlayer(url: videoURL)
///     let haptics = try HapticVideoSync(player: player, resource: "__AHAP_NAME__")
///     player.play()   // haptics follow play, pause, seek and rate changes
///
/// Add "__AHAP_NAME__.ahap" to your app target. Keep a strong reference to `HapticVideoSync`.
/// Haptics need a device with Core Haptics. Check `HapticVideoSync.isSupported` first.
final class HapticVideoSync {
    enum SyncError: Error { case unsupported, missingResource, invalidPattern }

    static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private let player: AVPlayer
    private let engine: CHHapticEngine
    private let pattern: CHHapticPattern
    private var active: CHHapticAdvancedPatternPlayer?
    private var rateObservation: NSKeyValueObservation?
    private var jumpObserver: NSObjectProtocol?
    private var driftTimer: Timer?
    /// Media time and engine time at the moment haptics last started. Used for drift checks.
    private var anchor: (media: TimeInterval, engine: TimeInterval)?

    /// Seconds of allowed drift before haptics are realigned.
    var driftTolerance: TimeInterval = 0.05

    convenience init(player: AVPlayer, resource: String, bundle: Bundle = .main) throws {
        guard Self.isSupported else { throw SyncError.unsupported }
        guard let url = bundle.url(forResource: resource, withExtension: "ahap") else { throw SyncError.missingResource }
        try self.init(player: player, ahapURL: url)
    }

    init(player: AVPlayer, ahapURL: URL) throws {
        guard Self.isSupported else { throw SyncError.unsupported }
        self.player = player
        let data = try Data(contentsOf: ahapURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let converted = Self.convert(json) as? [CHHapticPattern.Key: Any] else { throw SyncError.invalidPattern }
        pattern = try CHHapticPattern(dictionary: converted)
        engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak self] in
            // Engine was reset by the system. Start it again and realign.
            try? self?.engine.start()
            self?.realign()
        }
        engine.stoppedHandler = { _ in }
        try engine.start()

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.realign() }
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem, item === self?.player.currentItem else { return }
            self?.realign()
        }
        driftTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkDrift() }
        realign()
    }

    deinit {
        driftTimer?.invalidate()
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        stop()
        engine.stop(completionHandler: nil)
    }

    /// Stop haptics now.
    func stop() {
        try? active?.stop(atTime: CHHapticTimeImmediate)
        active = nil
        anchor = nil
    }

    /// Restart haptics from the video's current time, or stop when the video is paused.
    func realign() {
        stop()
        guard player.rate > 0 else { return }
        let media = player.currentTime().seconds
        guard media.isFinite, media >= 0 else { return }
        do {
            let p = try engine.makeAdvancedPlayer(with: pattern)
            p.playbackRate = player.rate
            try p.seek(toOffset: media)
            try p.start(atTime: CHHapticTimeImmediate)
            active = p
            anchor = (media, engine.currentTime)
        } catch {
            // Seeking past the last event can fail. Nothing left to play.
            active = nil
        }
    }

    private func checkDrift() {
        guard let anchor, player.rate > 0 else { return }
        let hapticMedia = anchor.media + (engine.currentTime - anchor.engine) * Double(player.rate)
        if abs(hapticMedia - player.currentTime().seconds) > driftTolerance { realign() }
    }

    /// AHAP JSON uses plain string keys. Core Haptics wants `CHHapticPattern.Key`.
    private static func convert(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [CHHapticPattern.Key: Any] = [:]
            for (k, v) in dict { out[CHHapticPattern.Key(rawValue: k)] = convert(v) }
            return out
        }
        if let array = value as? [Any] { return array.map(convert) }
        return value
    }
}
"""#
}
