// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import AppKit
import FeelCore
import Observation
import UniformTypeIdentifiers

/// State of the player app: one video, its haptics, and the phones that feel them.
@MainActor @Observable
final class PlayerModel: DeviceHost {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    let video = VideoEngine()
    let session = DeviceSession()

    private(set) var videoURL: URL?
    private(set) var metadata: VideoMetadata? { didSet { updateGraph() } }
    private(set) var events: [HapticEvent] = [] {
        didSet {
            session.eventsChanged(events)
            updateGraph()
        }
    }
    private(set) var hapticGraph: [Double] = []
    private(set) var isMaking = false
    var warning: String?
    /// Shown over the video. Opening a file with no clear sound is not worth an alert.
    var message: String?
    var errorMessage: String?
    var hapticsMuted = false { didSet { session.muted = hapticsMuted } }
    var audioMuted = false { didSet { video.player.isMuted = audioMuted } }
    private(set) var hapticAdvance: TimeInterval = 0
    private(set) var isScrubbing = false

    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterScrub = false

    init() {
        session.onRemote = { [weak self] cmd in Task { @MainActor in self?.handleRemote(cmd) } }
        session.startListening()
    }

    var hasVideo: Bool { videoURL != nil }
    var title: String { videoURL?.deletingPathExtension().lastPathComponent ?? "Feel Player" }

    private func updateGraph() {
        hapticGraph = HapticGraph.levels(events: events, duration: metadata?.duration ?? 0)
    }

    // MARK: Open

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(url) }
    }

    /// A video, or a haptics file for the open video.
    func open(_ url: URL) async {
        if url.pathExtension.lowercased() == "json" {
            loadHaptics(url)
        } else {
            await openVideo(url)
        }
    }

    func openVideo(_ url: URL) async {
        guard Self.videoExtensions.contains(url.pathExtension.lowercased()) else {
            errorMessage = "Unsupported file type. Use MP4, MOV, M4V, or a Feel haptics JSON file."
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        do {
            let meta = try await video.probe(url)
            close()
            if started { scopedURL = url }
            videoURL = url
            metadata = meta
            video.open(url, duration: meta.duration)
            session.setVideo(url)
            session.sendDuration(meta.duration)
            makeFromSound()
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            errorMessage = "Cannot open video: \(error.localizedDescription)"
        }
    }

    func close() {
        autoTask?.cancel()
        resyncTask?.cancel()
        isMaking = false
        warning = nil
        message = nil
        events = []
        video.close()
        session.setVideo(nil)
        session.sendDuration(0)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        videoURL = nil
        metadata = nil
    }

    // MARK: Haptics

    func loadHaptics(_ url: URL) {
        guard let meta = metadata else {
            errorMessage = "Open the video first, then its haptics file."
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do {
            let doc = try HapticShare.load(from: url)
            autoTask?.cancel()
            isMaking = false
            message = nil
            events = HapticShare.events(from: doc)
            switch HapticShare.match(doc, video: meta) {
            case .match, .unknown: warning = nil
            case .lengthDiffers(let expected, let actual):
                warning = "These haptics were made for a video of \(Timebase.format(expected)). This video is \(Timebase.format(actual)). Timing may be off."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearHaptics() {
        events = []
        warning = nil
    }

    func makeFromSound() {
        guard let url = videoURL, !isMaking else { return }
        autoTask?.cancel()
        isMaking = true
        message = nil
        autoTask = Task { [weak self] in
            let spectrum = await Task.detached(priority: .userInitiated) { await AudioSpectrumExtractor.extract(url: url) }.value
            guard !Task.isCancelled, let self else { return }
            self.isMaking = false
            guard let spectrum else {
                self.message = "Cannot read the sound of this video."
                return
            }
            let found = AudioHaptics.generate(spectrum: spectrum, sensitivity: 0.5)
            guard !found.isEmpty else {
                self.message = "No clear hits in the sound."
                return
            }
            self.events = found
            self.warning = nil
        }
    }

    // MARK: Playback

    var playBlocked: Bool { hasVideo && (isMaking || (session.isSyncing && session.videoBusy)) }

    func togglePlay() { video.isPlaying ? pause() : play() }

    func play() {
        guard hasVideo, !playBlocked else { return }
        if session.isSyncing {
            if video.currentTime >= video.duration - 0.01 { video.seek(to: 0, precise: true) }
            let mediaStart = video.currentTime
            // Start both devices at one future instant. Lead covers preroll and network.
            let host = SharedClock.now() + 0.4
            video.play(atHostTime: host)
            session.sendPlay(mediaTime: mediaStart, hostTime: host, advance: hapticAdvance)
            startResync()
        } else {
            video.play()
        }
    }

    func pause() {
        resyncTask?.cancel()
        video.pause()
        session.sendPause(mediaTime: video.exactTime)
    }

    func setHapticAdvance(_ seconds: TimeInterval) {
        hapticAdvance = min(max(seconds, -0.1), 0.3)
        if video.isPlaying, session.isSyncing { sendResync() }
    }

    func audition(_ event: HapticEvent) { session.audition(event) }

    private func startResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            var ticks = 0
            while !Task.isCancelled {
                guard let self else { return }
                if !self.video.isPlaying {
                    self.session.sendPause(mediaTime: self.video.exactTime)
                    return
                }
                if ticks % 8 == 0 { self.sendResync() }
                ticks += 1
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func sendResync() {
        let host = SharedClock.now()
        let media = video.exactTime
        session.sendPlay(mediaTime: media, hostTime: host, advance: hapticAdvance)
    }

    // MARK: Scrubbing

    func skip(by seconds: TimelineTime) {
        guard hasVideo, !isMaking else { return }
        let target = Timebase.clamp(video.currentTime + seconds, duration: video.duration)
        scrub(to: target)
        endScrub(at: target)
    }

    func scrub(to time: TimelineTime) {
        if !isScrubbing {
            resumeAfterScrub = video.isPlaying
            if resumeAfterScrub { pause() }
        }
        isScrubbing = true
        video.seek(to: time, precise: false)
    }

    func endScrub(at time: TimelineTime) {
        isScrubbing = false
        video.seek(to: time, precise: true)
        if resumeAfterScrub { resumeAfterScrub = false; play() } else { session.sendPause(mediaTime: time) }
    }

    /// Commands from a phone.
    private func handleRemote(_ cmd: DeviceSession.Remote) {
        guard hasVideo else { return }
        switch cmd {
        case .play: if !video.isPlaying { play() }
        case .pause: if video.isPlaying { pause() }
        case .seek(let t, let final):
            let time = min(max(t, 0), video.duration)
            if final {
                let resume = resumeAfterScrub
                endScrub(at: time)
                if !resume { session.sendPause(mediaTime: time) }
            } else {
                scrub(to: time)
            }
        }
    }
}
