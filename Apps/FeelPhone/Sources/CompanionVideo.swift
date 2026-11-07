// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import FeelCore
import Foundation
import Observation

/// Receives the video from the editor and plays it on the shared clock.
@MainActor @Observable
final class CompanionVideo {
    enum State: Equatable {
        case none
        case receiving(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .none
    private(set) var player: AVPlayer?
    var soundOn = false {
        didSet {
            Self.configureAudioSession()
            player?.isMuted = !soundOn
        }
    }

    /// Set by the model. Tells the editor how the transfer went.
    @ObservationIgnored var onReady: ((String) -> Void)?
    @ObservationIgnored var onFailed: ((String, String) -> Void)?

    @ObservationIgnored private var id: String?
    @ObservationIgnored private var size = 0
    @ObservationIgnored private var written = 0
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private var file: URL?

    /// Mix with other audio so the video never takes the session from the haptic engine.
    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: Receive

    func begin(id: String, name: String, size: Int) {
        clear()
        self.id = id
        self.size = size
        let ext = (name as NSString).pathExtension.isEmpty ? "mp4" : (name as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feel-\(UUID().uuidString).\(ext)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil), let h = try? FileHandle(forWritingTo: url) else {
            state = .failed("Cannot store video.")
            onFailed?(id, "Cannot store video.")
            return
        }
        file = url
        handle = h
        written = 0
        state = .receiving(0)
    }

    func append(id: String, offset: Int, data: Data) {
        guard id == self.id, let handle, offset == written else { return }
        do {
            try handle.write(contentsOf: data)
            written += data.count
            state = .receiving(Double(written) / Double(max(size, 1)))
        } catch {
            fail("Out of space.")
        }
    }

    func finish(id: String) {
        guard id == self.id, let url = file else { return }
        try? handle?.close()
        handle = nil
        guard written == size else { fail("Video transfer incomplete."); return }
        Self.configureAudioSession()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        p.isMuted = !soundOn
        player = p
        state = .ready
        onReady?(id)
    }

    private func fail(_ reason: String) {
        let failedID = id
        clear()
        state = .failed(reason)
        if let failedID { onFailed?(failedID, reason) }
    }

    func clear() {
        player?.pause()
        player = nil
        try? handle?.close()
        handle = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        id = nil
        written = 0
        state = .none
    }

    // MARK: Playback

    /// Media time `mediaTime` plays at editor host time `hostTime`. Offset maps editor clock to local clock.
    func play(mediaTime: TimelineTime, hostTime: TimeInterval, clockOffset: TimeInterval) {
        guard let p = player, state == .ready else { return }
        let now = SharedClock.now()
        let startLocal = hostTime - clockOffset
        if startLocal > now + 0.02 {
            // Start is ahead. Park on the first frame, then release at the shared instant.
            p.pause()
            p.seek(to: CMTime(seconds: mediaTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                p.setRate(1, time: CMTime(seconds: mediaTime, preferredTimescale: 600),
                          atHostTime: CMTime(seconds: startLocal, preferredTimescale: 1_000_000))
            }
            return
        }
        let position = mediaTime + (now - startLocal)
        let drift = abs(p.currentTime().seconds - position)
        guard p.rate == 0 || drift > 0.08 else { return }
        // Re-anchor 60 ms ahead so the call lands on time.
        let lead = 0.06
        p.setRate(1, time: CMTime(seconds: position + lead, preferredTimescale: 600),
                  atHostTime: CMTime(seconds: now + lead, preferredTimescale: 1_000_000))
    }

    func pause(at mediaTime: TimelineTime) {
        guard let p = player else { return }
        p.pause()
        p.seek(to: CMTime(seconds: mediaTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
