// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import FeelCore
import Observation

enum VideoError: LocalizedError {
    case notPlayable
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .notPlayable: "File cannot be played."
        case .noVideoTrack: "File has no video track."
        }
    }
}

/// Owns AVPlayer. Publishes time and play state on main actor.
@MainActor @Observable
final class VideoEngine {
    let player = AVPlayer()
    private(set) var currentTime: TimelineTime = 0
    private(set) var isPlaying = false
    private(set) var duration: TimelineTime = 0

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, t.isNumeric else { return }
                self.currentTime = t.seconds
            }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    /// Read metadata without changing playback.
    func probe(_ url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw VideoError.notPlayable }
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
        let (size, fps, transform) = try await track.load(.naturalSize, .nominalFrameRate, .preferredTransform)
        let oriented = size.applying(transform)
        return VideoMetadata(
            duration: duration,
            frameRate: Double(fps),
            width: Int(abs(oriented.width).rounded()),
            height: Int(abs(oriented.height).rounded())
        )
    }

    func open(_ url: URL, duration: TimelineTime) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        self.duration = duration
        currentTime = 0
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.currentTime = self?.duration ?? 0 }
        }
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        duration = 0
        currentTime = 0
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard player.currentItem != nil else { return }
        if currentTime >= duration - 0.01 { seek(to: 0, precise: true) }
        player.play()
    }

    /// Start playback exactly at host-clock time `host` (see `SharedClock`).
    func play(atHostTime host: TimeInterval) {
        guard player.currentItem != nil else { return }
        if currentTime >= duration - 0.01 { seek(to: 0, precise: true) }
        let when = CMTime(seconds: host, preferredTimescale: 1_000_000_000)
        player.preroll(atRate: 1) { [weak self] _ in
            Task { @MainActor in self?.player.setRate(1, time: .invalid, atHostTime: when) }
        }
    }

    func pause() { player.pause() }

    var exactTime: TimelineTime { player.currentTime().seconds }

    /// Fast seek while scrubbing, frame-accurate otherwise.
    func seek(to time: TimelineTime, precise: Bool) {
        let t = Timebase.clamp(time, duration: duration)
        currentTime = t
        let target = CMTime(seconds: t, preferredTimescale: 600)
        let tol: CMTime = precise ? .zero : .positiveInfinity
        player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol)
    }

    func step(frames: Int, frameRate: Double) {
        pause()
        seek(to: currentTime + Double(frames) / max(frameRate, 1), precise: true)
    }
}
