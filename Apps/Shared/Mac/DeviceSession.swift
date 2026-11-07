// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import AVFoundation
import FeelCore
import Foundation
import Observation
import os

/// One connected phone.
@MainActor @Observable
final class DeviceLink: Identifiable {
    let id = UUID()
    var name = "Device"
    var status: CompanionStatus?
    var video: DeviceSession.VideoTransfer = .none
    /// Hello received. Safe to send.
    var ready = false
    @ObservationIgnored let connection: FeelConnection
    @ObservationIgnored var sentVideoID: String?
    @ObservationIgnored var videoTask: Task<Void, Never>?

    init(connection: FeelConnection) { self.connection = connection }
}

/// Editor side. The Mac listens. Phones scan the QR code (or type the code) and join. Many at once.
@MainActor @Observable
final class DeviceSession {
    enum VideoTransfer: Equatable {
        case none, preparing, sending(Double), ready, failed(String)
    }

    enum Remote: Equatable { case play, pause, seek(TimelineTime, final: Bool) }

    private(set) var links: [DeviceLink] = []
    private(set) var code = PairingCode.generate()
    /// What the QR code holds. Empty until the listener is up.
    private(set) var joinLink = ""
    private(set) var listenError: String?

    /// User switch. Off = links stay up, nothing is sent.
    var previewOn = true { didSet { if previewOn != oldValue { previewChanged() } } }
    var muted = false { didSet { if muted != oldValue { pushEvents(force: true) } } }
    /// Send a 720p copy of the video so phones play it with the haptics.
    var shareVideo = true { didSet { if shareVideo != oldValue { videoSourceChanged() } } }

    var readyLinks: [DeviceLink] { links.filter(\.ready) }
    var isConnected: Bool { !readyLinks.isEmpty }
    /// Haptics should follow video playback.
    var isSyncing: Bool { isConnected && previewOn && !muted }

    /// Some phone is still getting the video.
    var videoBusy: Bool {
        guard shareVideo else { return false }
        return readyLinks.contains { if case .preparing = $0.video { true } else if case .sending = $0.video { true } else { false } }
    }

    /// Slowest phone, 0...1. nil when nobody is sending.
    var videoProgress: Double? {
        let p = readyLinks.compactMap { l -> Double? in
            switch l.video {
            case .sending(let x): x
            case .preparing: 0
            default: nil
            }
        }
        return p.min()
    }

    /// iPhone or Android asked to play, pause or seek.
    @ObservationIgnored var onRemote: ((Remote) -> Void)?
    @ObservationIgnored private let listener: FeelListenerHolder = FeelListenerHolder()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var latest: [HapticEvent] = []
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var timelineDuration: TimelineTime = 0
    @ObservationIgnored private var videoURL: URL?
    @ObservationIgnored private var prepTask: Task<URL?, Never>?
    @ObservationIgnored private var prepSource: URL?
    @ObservationIgnored private var shareCopy: (source: URL, file: URL)?
    @ObservationIgnored private let hostName = Host.current().localizedName ?? "Mac"

    // MARK: Listening

    func startListening() {
        guard listener.value == nil else { return }
        let l = FeelListener(name: hostName, code: code)
        l.onConnection = { [weak self] conn in Task { @MainActor in self?.accept(conn) } }
        l.onState = { [weak self, weak l] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listenError = nil
                    if let port = l?.port, let ip = LocalNetwork.ipv4() {
                        self.joinLink = JoinLink(host: ip, port: port, code: self.code, name: self.hostName).url
                        #if DEBUG
                        Logger(subsystem: "com.feelplayer.mac", category: "join").info("joinlink \(self.joinLink, privacy: .public)")
                        #endif
                    } else {
                        self.listenError = "No Wi-Fi address found. Connect the Mac to your network."
                    }
                case .failed(let e):
                    self.listenError = "Network error: \(e.localizedDescription)"
                    self.listener.value = nil
                    self.joinLink = ""
                case .waiting(let e):
                    self.listenError = "Network unavailable: \(e.localizedDescription)"
                default: break
                }
            }
        }
        do {
            try l.start()
            listener.value = l
        } catch {
            listenError = "Cannot start: \(error.localizedDescription)"
        }
    }

    /// New code. Phones that are connected stay. New joins need the new code.
    func resetCode() {
        listener.value?.stop()
        listener.value = nil
        joinLink = ""
        code = PairingCode.generate()
        startListening()
    }

    // MARK: Connections

    private func accept(_ conn: FeelConnection) {
        let link = DeviceLink(connection: conn)
        links.append(link)
        conn.onMessage = { [weak self, weak conn] msg, stamp in
            // Answer clock pings before hopping threads. Stamps stay tight.
            if case .ping(let id, let t0) = msg, let conn {
                conn.send(.pong(id: id, t0: t0, t1: stamp, t2: SharedClock.now()))
                return
            }
            Task { @MainActor in self?.handle(msg, from: link) }
        }
        conn.onState = { [weak self] s in Task { @MainActor in self?.connectionState(s, link) } }
        conn.start()
    }

    private func connectionState(_ s: FeelConnection.State, _ link: DeviceLink) {
        switch s {
        case .ready:
            link.connection.send(.hello(Hello(name: hostName, role: .editor, supportsHaptics: false)))
        case .failed, .closed:
            remove(link)
        default: break
        }
    }

    private func remove(_ link: DeviceLink) {
        link.videoTask?.cancel()
        link.connection.cancel()
        links.removeAll { $0.id == link.id }
    }

    func disconnect(_ link: DeviceLink) {
        link.connection.send(.bye)
        remove(link)
    }

    func disconnectAll() {
        for l in links { l.connection.send(.bye) }
        for l in links { remove(l) }
    }

    private func handle(_ msg: Message, from link: DeviceLink) {
        guard links.contains(where: { $0.id == link.id }) else { return }
        switch msg {
        case .hello(let h):
            link.name = h.name
            link.ready = true
            if previewOn { link.connection.send(.pattern(revision: nextRevision(), events: muted ? [] : latest)) }
            link.connection.send(.timeline(duration: timelineDuration))
            startVideo(for: link)
        case .status(let s):
            link.status = s
        case .videoReady(let id):
            if id == link.sentVideoID { link.video = .ready }
        case .videoFailed(let id, let reason):
            if id == link.sentVideoID { link.video = .failed(reason) }
        case .remotePlay: onRemote?(.play)
        case .remotePause: onRemote?(.pause)
        case .remoteSeek(let t, let final): onRemote?(.seek(t, final: final))
        case .bye: remove(link)
        default: break
        }
    }

    private func broadcast(_ m: Message) {
        for l in readyLinks { l.connection.send(m) }
    }

    private func nextRevision() -> Int { revision += 1; return revision }

    // MARK: State sync

    /// Batched. Many edits in 40 ms become one message.
    func eventsChanged(_ events: [HapticEvent]) {
        latest = events
        pushEvents(force: false)
    }

    private func pushEvents(force: Bool) {
        guard isConnected, previewOn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if !force { try? await Task.sleep(for: .milliseconds(40)) }
            guard !Task.isCancelled, let self, self.isConnected else { return }
            let rev = self.nextRevision()
            self.broadcast(.pattern(revision: rev, events: self.muted ? [] : self.latest))
        }
    }

    private func previewChanged() {
        if previewOn { pushEvents(force: true) } else { broadcast(.pause(mediaTime: 0)) }
    }

    func setLatest(_ events: [HapticEvent]) { latest = events }

    func sendDuration(_ d: TimelineTime) {
        timelineDuration = d
        broadcast(.timeline(duration: d))
    }

    func sendPlay(mediaTime: TimelineTime, hostTime: TimeInterval, advance: TimeInterval) {
        guard isSyncing else { return }
        broadcast(.play(mediaTime: mediaTime, hostTime: hostTime, advance: advance))
    }

    func sendPause(mediaTime: TimelineTime) {
        guard isConnected else { return }
        broadcast(.pause(mediaTime: mediaTime))
    }

    func audition(_ event: HapticEvent) {
        guard isSyncing else { return }
        broadcast(.audition(event))
    }

    // MARK: Video share

    /// The video now open in the editor. nil = none.
    func setVideo(_ url: URL?) {
        videoURL = url
        // Make the share copy now, before anyone joins, so sending starts at once.
        if let url {
            if prepSource != url {
                prepSource = url
                prepTask = Task { [weak self] in await self?.shareFile(for: url) }
            }
        } else {
            prepTask?.cancel()
            prepTask = nil
            prepSource = nil
        }
        videoSourceChanged()
    }

    private func videoSourceChanged() {
        for l in readyLinks { startVideo(for: l) }
    }

    private func startVideo(for link: DeviceLink) {
        link.videoTask?.cancel()
        guard let url = videoURL, shareVideo else {
            link.connection.send(.videoClear)
            link.video = .none
            return
        }
        link.video = .preparing
        let conn = link.connection
        link.videoTask = Task { [weak self, weak link] in
            guard let self, let link else { return }
            do {
                let file: URL
                let prepared: URL?
                if let prep = self.prepTask { prepared = await prep.value } else { prepared = await self.shareFile(for: url) }
                try Task.checkCancellation()
                guard let ready = prepared else {
                    link.video = .failed("This video cannot play on a phone. Convert it to H.264 or HEVC.")
                    return
                }
                file = ready
                let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
                guard size > 0 else { throw CocoaError(.fileReadUnknown) }
                let id = UUID().uuidString
                link.sentVideoID = id
                conn.send(.videoOffer(id: id, name: file.lastPathComponent, size: size))
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var offset = 0
                while let data = try handle.read(upToCount: 384 * 1024), !data.isEmpty {
                    try Task.checkCancellation()
                    await conn.sendAndWait(.videoChunk(id: id, offset: offset, data: data))
                    offset += data.count
                    link.video = .sending(Double(offset) / Double(size))
                }
                conn.send(.videoEnd(id: id))
            } catch is CancellationError {
            } catch {
                link.video = .failed("Could not send video.")
            }
        }
    }

    /// Phones cannot decode every codec the Mac can. AV1 and VP9 video and Opus sound need a conversion.
    private func phoneNeedsConversion(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        let video = ((try? await asset.loadTracks(withMediaType: .video)) ?? [])
        let audio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? [])
        for track in video {
            for d in (try? await track.load(.formatDescriptions)) ?? [] {
                let t = CMFormatDescriptionGetMediaSubType(d)
                if t == kCMVideoCodecType_AV1 || t == kCMVideoCodecType_VP9 { return true }
            }
        }
        for track in audio {
            for d in (try? await track.load(.formatDescriptions)) ?? [] where CMFormatDescriptionGetMediaSubType(d) == kAudioFormatOpus { return true }
        }
        return false
    }

    /// File to send to phones. nil = no copy a phone can play.
    /// Small phone-safe files go as they are. Others become a 720p H.264 copy.
    private func shareFile(for url: URL) async -> URL? {
        let convert = await phoneNeedsConversion(url)
        // Small files go as they are. No wait for an export.
        if !convert, let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size < 50_000_000 { return url }
        if let c = shareCopy, c.source == url, FileManager.default.fileExists(atPath: c.file.path) { return c.file }
        if let old = shareCopy { try? FileManager.default.removeItem(at: old.file) }
        shareCopy = nil
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("feel-share-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPreset1280x720) else { return convert ? nil : url }
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        // A failed export of a file the phone cannot play must not fall back to the original.
        guard export.status == .completed else { return convert ? nil : url }
        shareCopy = (url, out)
        return out
    }
}

/// Reference box so the listener can be set from non-isolated closures.
final class FeelListenerHolder: @unchecked Sendable {
    var value: FeelListener?
}
