// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import FeelCore
import Foundation
import Observation

/// Plays a video from this phone with haptics. No Mac needed.
@MainActor @Observable
final class SoloModel {
    private(set) var player: AVPlayer?
    private(set) var name = ""
    private(set) var duration: TimelineTime = 0 { didSet { updateGraph() } }
    private(set) var mediaTime: TimelineTime = 0
    private(set) var isPlaying = false
    private(set) var events: [HapticEvent] = [] { didSet { updateGraph() } }
    private(set) var hapticGraph: [Double] = []
    private(set) var isMaking = false
    private(set) var metadata: VideoMetadata?
    var message: String?
    var warning: String?
    var soundOn = true { didSet { player?.isMuted = !soundOn } }

    let haptics = HapticPlayer()

    @ObservationIgnored private var videoURL: URL?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var makeTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var resumeAfterSeek = false

    /// Seconds of pattern scheduled per window. Core Haptics copes best with bounded patterns.
    private let window: TimelineTime = 30
    private let lead: TimeInterval = 0.2

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    var hasVideo: Bool { player != nil }

    private func updateGraph() {
        hapticGraph = HapticGraph.levels(events: events, duration: duration)
    }

    // MARK: Open

    func open(_ url: URL) async {
        if url.pathExtension.lowercased() == "json" {
            loadHaptics(url)
        } else {
            await openVideo(url)
        }
    }

    private func openVideo(_ url: URL) async {
        guard Self.videoExtensions.contains(url.pathExtension.lowercased()) else {
            message = "Unsupported file. Use MP4, MOV, M4V, or a Feel haptics JSON file."
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        let asset = AVURLAsset(url: url)
        do {
            let length = try await asset.load(.duration).seconds
            guard length.isFinite, length > 0, let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // The sound plays even when the picture cannot be decoded. Refuse, or the screen stays black.
            guard try await track.load(.isDecodable), try await asset.load(.isPlayable) else {
                let codec = ((try? await track.load(.formatDescriptions)) ?? []).first.map { Self.codecName(CMFormatDescriptionGetMediaSubType($0)) }
                message = "This iPhone cannot show \(codec ?? "this") video. Use an H.264 or HEVC file (MP4 or MOV)."
                if started { url.stopAccessingSecurityScopedResource() }
                return
            }
            let size = try await track.load(.naturalSize)
            let rate = try await track.load(.nominalFrameRate)
            close()
            if started { scopedURL = url }
            videoURL = url
            name = url.deletingPathExtension().lastPathComponent
            duration = length
            metadata = VideoMetadata(duration: length, frameRate: Double(rate), width: Int(size.width), height: Int(size.height))
            await Self.configureAudioSession()
            let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            p.automaticallyWaitsToMinimizeStalling = false
            p.isMuted = !soundOn
            player = p
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished() }
            }
            haptics.prepare()
            message = nil
            makeFromSound()
            #if DEBUG
            Task { await diagnose(asset: asset, player: p) }
            #endif
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            message = "Cannot open this video."
        }
    }

    private static func codecName(_ type: FourCharCode) -> String {
        switch type {
        case 0x61763031: "AV1" // 'av01'
        case 0x76703039: "VP9" // 'vp09'
        default: String(format: "%c%c%c%c", (type >> 24) & 255, (type >> 16) & 255, (type >> 8) & 255, type & 255)
        }
    }

    /// Mix with other audio so the video never takes the session from the haptic engine.
    /// Off the main thread: activating the session can block.
    private static func configureAudioSession() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? session.setActive(true)
        }.value
    }

    #if DEBUG
    private func diagnose(asset: AVURLAsset, player p: AVPlayer) async {
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        for t in tracks {
            let codec = ((try? await t.load(.formatDescriptions)) ?? []).map { CMFormatDescriptionGetMediaSubType($0) }
            let size = try? await t.load(.naturalSize)
            let playable = try? await asset.load(.isPlayable)
            print("[Solo] track codec=\(codec) size=\(String(describing: size)) playable=\(String(describing: playable))")
        }
        try? await Task.sleep(for: .seconds(1))
        let item = p.currentItem
        print("[Solo] status=\(String(describing: item?.status.rawValue)) error=\(String(describing: item?.error)) presentation=\(String(describing: item?.presentationSize))")
        if let log = item?.errorLog() { print("[Solo] errorLog=\(log.events.map { $0.errorComment ?? "-" })") }
    }
    #endif

    func close() {
        stop()
        makeTask?.cancel()
        isMaking = false
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        events = []
        warning = nil
        mediaTime = 0
        duration = 0
        metadata = nil
        videoURL = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    // MARK: Haptics

    private func loadHaptics(_ url: URL) {
        guard let meta = metadata else {
            message = "Open the video first, then its haptics file."
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            let doc = try HapticShare.load(from: url)
            makeTask?.cancel()
            isMaking = false
            setEvents(HapticShare.events(from: doc))
            switch HapticShare.match(doc, video: meta) {
            case .match, .unknown: warning = nil
            case .lengthDiffers(let expected, let actual):
                warning = "Made for a video of \(Timebase.format(expected)). This one is \(Timebase.format(actual)). Timing may be off."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func setEvents(_ new: [HapticEvent]) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        events = new
        if wasPlaying { play() }
    }

    func clearHaptics() {
        setEvents([])
        warning = nil
    }

    func makeFromSound() {
        guard let url = videoURL, !isMaking else { return }
        makeTask?.cancel()
        isMaking = true
        makeTask = Task { [weak self] in
            let spectrum = await Task.detached(priority: .userInitiated) { await AudioSpectrumExtractor.extract(url: url) }.value
            guard !Task.isCancelled, let self else { return }
            self.isMaking = false
            guard let spectrum else { self.message = "Cannot read the sound of this video."; return }
            let found = AudioHaptics.generate(spectrum: spectrum, sensitivity: 0.5)
            guard !found.isEmpty else { self.message = "No clear hits in the sound."; return }
            self.setEvents(found)
            self.warning = nil
        }
    }

    // MARK: Playback

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let p = player, !isPlaying else { return }
        if mediaTime >= duration - 0.05 { p.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero); mediaTime = 0 }
        let start = mediaTime
        isPlaying = true
        startTicking()
        let target = CMTime(seconds: start, preferredTimescale: 600)
        // Park on the exact frame, then release video and haptics at one instant.
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                let at = SharedClock.now() + self.lead
                p.setRate(1, time: target, atHostTime: CMTime(seconds: at, preferredTimescale: 1_000_000))
                self.schedule(from: start, delay: self.lead)
            }
        }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        stop()
        if let p = player { mediaTime = p.currentTime().seconds }
    }

    private func stop() {
        isPlaying = false
        tickTask?.cancel()
        windowTask?.cancel()
        haptics.stopAll()
    }

    private func finished() {
        stop()
        mediaTime = duration
    }

    /// Haptics for the next window. Rebuilt a little before it ends.
    private func schedule(from start: TimelineTime, delay: TimeInterval) {
        windowTask?.cancel()
        haptics.play(events: events, from: start, to: start + window, delay: delay)
        let wait = max(window - 4 + delay, 1)
        windowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.isPlaying, let p = self.player else { return }
            self.schedule(from: p.currentTime().seconds, delay: 0.05)
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, let p = self.player, p.rate > 0 { self.mediaTime = min(p.currentTime().seconds, self.duration) }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    // MARK: Seek

    func seek(to t: TimelineTime, final: Bool) {
        guard let p = player else { return }
        let clamped = min(max(t, 0), duration)
        // Haptics are scheduled from the playhead, so a seek always restarts them.
        if isPlaying { resumeAfterSeek = true; pause() }
        mediaTime = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        if final {
            p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            if resumeAfterSeek { resumeAfterSeek = false; play() }
        } else {
            p.seek(to: target)
        }
    }

    func testHaptic() {
        haptics.prepare()
        haptics.audition(HapticEvent(type: .tap, start: 0, intensity: 1, sharpness: 0.8))
    }
}
