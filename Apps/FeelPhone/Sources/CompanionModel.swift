// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class CompanionModel {
    enum Link: Equatable {
        case idle
        case connecting(String)
        case connected(editor: String)
    }

    private struct Target {
        var host: String?
        var port: UInt16?
        var device: FeelBrowser.Device?
        var code: String
        var name: String
    }

    private(set) var link: Link = .idle
    private(set) var macs: [FeelBrowser.Device] = []
    private(set) var error: String?
    private(set) var isPlaying = false
    private(set) var mediaTime: TimelineTime = 0
    private(set) var engineReady = false
    private(set) var rtt: TimeInterval?
    private(set) var notice: String?
    private(set) var eventCount = 0
    private(set) var debugLine = ""
    private(set) var duration: TimelineTime = 0 { didSet { if duration != oldValue { updateGraph() } } }
    private(set) var hapticGraph: [Double] = []

    /// How hard the haptic under the playhead hits, 0...1. For display only.
    var hapticLevel: Double { isPlaying ? events.level(at: mediaTime) : 0 }

    let player = HapticPlayer()
    let video = CompanionVideo()
    let deviceName = UIDevice.current.name

    @ObservationIgnored private let browser = FeelBrowser()
    @ObservationIgnored private var browsing = false
    @ObservationIgnored private var target: Target?
    @ObservationIgnored private var userClosed = false
    @ObservationIgnored private var everConnected = false
    @ObservationIgnored private var attempts = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var connection: FeelConnection?
    @ObservationIgnored private var clock = ClockSync()
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var uiTask: Task<Void, Never>?
    @ObservationIgnored private var events: [HapticEvent] = [] { didSet { updateGraph() } }
    @ObservationIgnored private var revision = -1
    @ObservationIgnored private var transport: Transport?
    @ObservationIgnored private var nextPing = 0

    private struct Transport {
        var mediaTime: Double
        var hostTime: Double
        var advance: Double
    }

    /// Seconds of pattern scheduled per window. Core Haptics copes best with bounded patterns.
    private let window: TimelineTime = 30

    init() {
        player.onDebug = { [weak self] line in self?.debugLine = line }
        video.onReady = { [weak self] id in self?.connection?.send(.videoReady(id: id)) }
        video.onFailed = { [weak self] id, reason in self?.connection?.send(.videoFailed(id: id, reason: reason)) }
        player.onReadyChange = { [weak self] ready, msg in
            self?.engineReady = ready
            self?.notice = msg
            self?.sendStatus()
        }
        player.onRestart = { [weak self] in self?.reschedule() }
    }

    // MARK: Lifecycle

    func start() {
        player.prepare()
        engineReady = player.isReady
    }

    /// Looks for Macs. Triggers the local network prompt, so only call it for someone who wants a Mac.
    func startBrowsing() {
        browsing = true
        browser.onUpdate = { [weak self] list in Task { @MainActor in self?.macs = list } }
        browser.start()
    }

    /// Call on foreground.
    func resume() {
        player.prepare()
        if !player.isReady { player.restart() }
        if browsing, link == .idle { browser.start() }
    }

    /// From the Mac's QR code.
    func connect(_ join: JoinLink) {
        begin(Target(host: join.host, port: join.port, device: nil, code: join.code, name: join.name))
    }

    /// A Mac picked from the list, with the code shown on the Mac.
    func connect(to device: FeelBrowser.Device, code: String) {
        begin(Target(host: nil, port: nil, device: device, code: code, name: device.name))
    }

    private func begin(_ t: Target) {
        userClosed = false
        everConnected = false
        attempts = 0
        error = nil
        target = t
        open()
    }

    private func open() {
        guard let t = target else { return }
        connection?.cancel()
        let conn: FeelConnection
        if let device = t.device {
            conn = FeelConnection.connect(to: device.endpoint, code: t.code)
        } else if let host = t.host, let port = t.port {
            conn = FeelConnection.connect(host: host, port: port, code: t.code)
        } else { return }
        connection = conn
        link = .connecting(t.name)
        clock.reset()
        rtt = nil
        // New editor session. Its revision numbers start over.
        revision = -1
        events = []
        eventCount = 0
        conn.onMessage = { [weak self] msg, stamp in
            Task { @MainActor in self?.handle(msg, receivedAt: stamp, from: conn) }
        }
        conn.onState = { [weak self] state in
            Task { @MainActor in self?.connectionState(state, conn) }
        }
        conn.start()
    }

    private func connectionState(_ state: FeelConnection.State, _ conn: FeelConnection) {
        guard conn === connection else { return }
        switch state {
        case .ready:
            conn.send(.hello(Hello(name: deviceName, role: .companion, supportsHaptics: player.supportsHaptics)))
            startPinging()
        case .waiting:
            if !everConnected { failConnect() }
        case .failed, .closed:
            lost()
        default: break
        }
    }

    private func failConnect() {
        connection?.cancel()
        connection = nil
        dropConnection()
        link = .idle
        error = "Could not connect. Check the code and that both devices share Wi-Fi."
    }

    /// Link ended. Try again if it was a good one.
    private func lost() {
        dropConnection()
        guard !userClosed, let t = target else { link = .idle; return }
        guard everConnected, attempts < 6 else {
            link = .idle
            error = "Could not connect. Check the code and that both devices share Wi-Fi."
            return
        }
        attempts += 1
        link = .connecting(t.name)
        let delay = min(pow(2, Double(attempts - 1)), 15)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.userClosed, self.connection == nil else { return }
            self.open()
        }
    }

    func reportError(_ message: String) { error = message }

    func disconnect() {
        userClosed = true
        retryTask?.cancel()
        connection?.send(.bye)
        dropConnection()
        target = nil
        link = .idle
    }

    private func dropConnection() {
        pingTask?.cancel(); windowTask?.cancel(); uiTask?.cancel()
        connection?.cancel()
        connection = nil
        player.stopAll()
        video.clear()
        transport = nil
        isPlaying = false
        duration = 0
        rtt = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Messages

    private func handle(_ msg: Message, receivedAt: TimeInterval, from conn: FeelConnection) {
        guard conn === connection else { return }
        switch msg {
        case .hello(let h):
            link = .connected(editor: h.name)
            everConnected = true
            attempts = 0
            error = nil
            UIApplication.shared.isIdleTimerDisabled = true
            sendStatus()
        case .pong(let id, let t0, let t1, let t2):
            _ = id
            clock.add(t0: t0, t1: t1, t2: t2, t3: receivedAt)
            rtt = clock.rtt
        case .pattern(let rev, let evs):
            guard rev > revision else { return }
            revision = rev
            events = evs
            eventCount = evs.count
            if isPlaying { reschedule() }
        case .play(let m, let h, let adv):
            applyPlay(Transport(mediaTime: m, hostTime: h, advance: adv))
        case .pause(let mediaTime):
            transport = nil
            isPlaying = false
            windowTask?.cancel(); uiTask?.cancel()
            player.stopAll()
            video.pause(at: mediaTime)
            self.mediaTime = mediaTime
            sendStatus()
        case .audition(let e):
            player.audition(e)
        case .bye:
            userClosed = true
            dropConnection()
            target = nil
            link = .idle
        case .videoOffer(let id, let name, let size):
            video.begin(id: id, name: name, size: size)
        case .videoChunk(let id, let offset, let data):
            video.append(id: id, offset: offset, data: data)
        case .videoEnd(let id):
            video.finish(id: id)
        case .videoClear:
            video.clear()
        case .timeline(let d):
            duration = d
        case .ping, .status, .videoReady, .videoFailed, .remotePlay, .remotePause, .remoteSeek:
            break
        }
    }

    // MARK: Clock sync

    private func startPinging() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            var burst = 0
            while !Task.isCancelled {
                guard let self, let conn = self.connection else { return }
                self.nextPing += 1
                conn.send(.ping(id: self.nextPing, t0: SharedClock.now()))
                burst += 1
                self.sendStatus()
                try? await Task.sleep(for: .milliseconds(burst < 12 ? 120 : 2000))
            }
        }
    }

    private func sendStatus() {
        connection?.send(.status(CompanionStatus(playing: isPlaying, engineReady: engineReady, rtt: rtt, message: notice)))
    }

    // MARK: Playback

    private func position(of t: Transport, now: TimeInterval) -> TimelineTime? {
        guard let off = clock.offset else { return nil }
        return PlaybackPlan.position(mediaTime: t.mediaTime, editorHostTime: t.hostTime, advance: t.advance, clockOffset: off, nowLocal: now)
    }

    private func applyPlay(_ new: Transport) {
        guard clock.offset != nil else { return } // wait for first pong. Editor resends.
        let now = SharedClock.now()
        if let off = clock.offset { video.play(mediaTime: new.mediaTime, hostTime: new.hostTime, clockOffset: off) }
        // Small drift on a running transport: keep current schedule.
        if isPlaying, let old = transport, let a = position(of: old, now: now), let b = position(of: new, now: now), abs(a - b) < 0.04 {
            transport = new
            return
        }
        transport = new
        isPlaying = true
        reschedule()
        startUI()
        sendStatus()
    }

    /// Cancel and rebuild scheduled haptics from the current transport and clock.
    private func reschedule() {
        windowTask?.cancel()
        guard let t = transport, let off = clock.offset else { return }
        let plan = PlaybackPlan.make(mediaTime: t.mediaTime, editorHostTime: t.hostTime, advance: t.advance,
                                     clockOffset: off, nowLocal: SharedClock.now())
        player.play(events: events, from: plan.mediaStart, to: plan.mediaStart + window, delay: plan.delay)
        // Next window starts shortly before this one ends.
        let wait = max(window - 4 + plan.delay, 1)
        windowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.reschedule()
        }
    }

    private func startUI() {
        uiTask?.cancel()
        uiTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, let t = self.transport, let p = self.position(of: t, now: SharedClock.now()) {
                    self.mediaTime = max(p + t.advance, 0)
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func updateGraph() {
        hapticGraph = HapticGraph.levels(events: events, duration: duration)
    }

    // MARK: Remote control

    func togglePlay() {
        connection?.send(isPlaying ? .remotePause : .remotePlay)
    }

    /// While dragging, `final` is false. The Mac shows the frame. Release resumes if it was playing.
    func seek(to t: TimelineTime, final: Bool) {
        let clamped = min(max(t, 0), duration)
        mediaTime = clamped
        if !isPlaying || final { video.pause(at: clamped) }
        connection?.send(.remoteSeek(mediaTime: clamped, final: final))
    }

    // MARK: Test

    func testHaptic() {
        player.prepare()
        player.audition(HapticEvent(type: .tap, start: 0, intensity: 1, sharpness: 0.8))
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            player.audition(HapticEvent(type: .rumble, start: 0, duration: 0.6, intensity: 0.7, sharpness: 0.3, fadeIn: 0.1, fadeOut: 0.3))
        }
    }
}
