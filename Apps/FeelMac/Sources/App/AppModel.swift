// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import AppKit
import FeelCore
import Observation
import UniformTypeIdentifiers

enum VideoState: Equatable {
    case none
    case loaded
    case missing(URL)
    case failed(String)
}

/// Panels that float over the stage.
enum StagePanel: String, CaseIterable {
    case library = "Library", suggest = "Suggestions", project = "Project"

    var title: String { rawValue }

    var symbol: String {
        switch self {
        case .library: "square.stack"
        case .suggest: "sparkles"
        case .project: "info.circle"
        }
    }
}

@MainActor @Observable
final class AppModel: DeviceHost {
    var hapticAdvance: TimeInterval { project.settings.hapticAdvance }
    var project = HapticProject() {
        didSet {
            if project.events != oldValue.events { session.eventsChanged(project.events) }
            if !suppressDirty { markDirty() }
        }
    }
    private(set) var fileURL: URL?
    private(set) var isDirty = false
    private(set) var videoState: VideoState = .none
    var errorMessage: String?
    var isScrubbing = false
    var selection: Set<UUID> = []
    var canUndo = false
    var canRedo = false
    var stagePanel: StagePanel?

    let video = VideoEngine()
    let thumbs = ThumbnailStore()
    let waveform = WaveformStore()
    var audioMuted = false { didSet { video.player.isMuted = audioMuted } }
    var hapticsMuted = false { didSet { session.muted = hapticsMuted } }
    let session = DeviceSession()
    // Analysis
    enum AnalysisState: Equatable { case idle, running(Double), done, failed(String) }
    var suggestions: [HapticSuggestion] = []
    var analysisState: AnalysisState = .idle
    var sensitivity = 0.5 { didSet { if sensitivity != oldValue { rerunSuggester() } } }
    /// Scene cuts rarely deserve haptics. Hidden until the user asks.
    var shownKinds: Set<SuggestionKind> = Set(SuggestionKind.allCases).subtracting([.sceneCut])
    private(set) var activeVideoURL: URL?
    @ObservationIgnored var analysisInput: AnalysisInput?
    private(set) var isAutoRunning = false
    @ObservationIgnored var autoTask: Task<Void, Never>?
    @ObservationIgnored var spectrumCache: (url: URL, spectrum: AudioSpectrum)?
    @ObservationIgnored var analysisTask: Task<Void, Never>?
    @ObservationIgnored let analyzer = VideoAnalyzer()
    @ObservationIgnored var auditionTask: Task<Void, Never>?
    @ObservationIgnored var resyncTask: Task<Void, Never>?
    @ObservationIgnored var resumeAfterScrub = false
    @ObservationIgnored var lastScrub: TimelineTime?

    @ObservationIgnored private let store = ProjectStore()
    @ObservationIgnored private var suppressDirty = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored var history = EditHistory<[HapticEvent]>()
    @ObservationIgnored var lastEditKey: String?
    @ObservationIgnored var lastEditTime = Date.distantPast
    @ObservationIgnored var moveOrigins: [UUID: TimelineTime] = [:]
    @ObservationIgnored var moveRecorded = false

    init() {
        session.onRemote = { [weak self] cmd in Task { @MainActor in self?.handleRemote(cmd) } }
        session.startListening()
    }

    /// Commands from the iPhone.
    private func handleRemote(_ cmd: DeviceSession.Remote) {
        guard videoState == .loaded else { return }
        switch cmd {
        case .play: if !video.isPlaying { play() }
        case .pause: if video.isPlaying { pause() }
        case .seek(let t, let final):
            let time = min(max(t, 0), project.duration)
            if final {
                let resume = resumeAfterScrub
                endScrub(at: time)
                if !resume { session.sendPause(mediaTime: time) }
            } else {
                scrub(to: time)
            }
        }
    }

    func resetEditing() {
        history.reset()
        selection = []
        lastEditKey = nil
        canUndo = false
        canRedo = false
    }

    static let projectType = UTType(filenameExtension: ProjectStore.fileExtension, conformingTo: .json) ?? .json
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Nothing to edit yet. The window shows only the drop target.
    var isWelcome: Bool { videoState == .none && project.events.isEmpty }

    func toggle(_ panel: StagePanel) { stagePanel = stagePanel == panel ? nil : panel }

    var windowTitle: String { project.name + (isDirty ? " — Edited" : "") }
    var zoom: Double {
        get { project.timeline.zoom }
        set { project.timeline.zoom = min(max(newValue, 10), 800) }
    }

    // MARK: Project lifecycle

    func newProject() {
        releaseVideo()
        mutateQuietly { project = HapticProject() }
        resetEditing()
        fileURL = nil
        isDirty = false
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openProject(at: url) }
    }

    func openProject(at url: URL) async {
        do {
            let loaded = try store.load(from: url)
            releaseVideo()
            mutateQuietly { project = loaded }
            resetEditing()
            fileURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            await resolveVideo()
        } catch {
            errorMessage = "Cannot open project: \(error.localizedDescription)"
        }
    }

    func save() {
        guard let fileURL else { return saveAs() }
        write(to: fileURL)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = project.name + "." + ProjectStore.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
        fileURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func duplicateProject() {
        let copy = store.duplicate(project, name: project.name + " Copy")
        mutateQuietly { project = copy }
        resetEditing()
        fileURL = nil
        isDirty = true
        saveAs()
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else { return }
        project.name = trimmed
        // Keep the file name in step. Sandbox may refuse. Then only the project name changes.
        if let url = fileURL {
            let target = url.deletingLastPathComponent().appendingPathComponent(trimmed).appendingPathExtension(ProjectStore.fileExtension)
            guard target != url, !FileManager.default.fileExists(atPath: target.path) else { return }
            do {
                try FileManager.default.moveItem(at: url, to: target)
                fileURL = target
            } catch {
                errorMessage = "Project renamed. The file could not be renamed. Use Save As to choose a new file name."
            }
        }
    }

    private func write(to url: URL) {
        do {
            try store.save(project, to: url)
            isDirty = false
            removeRecoveryCopy()
        } catch {
            errorMessage = "Cannot save: \(error.localizedDescription)"
        }
    }

    // MARK: Autosave

    private func markDirty() {
        isDirty = true
        guard project.settings.autosave else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.autosaveNow()
        }
    }

    /// Saves in place when project has a file. Otherwise writes a recovery copy.
    private func autosaveNow() {
        if let fileURL {
            write(to: fileURL)
        } else if let dir = Self.recoveryDirectory {
            let url = dir.appendingPathComponent("\(project.id.uuidString).\(ProjectStore.fileExtension)")
            try? store.save(project, to: url)
        }
    }

    private func removeRecoveryCopy() {
        guard let dir = Self.recoveryDirectory else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(project.id.uuidString).\(ProjectStore.fileExtension)"))
    }

    /// Offer the newest unsaved project left by a crash or quit.
    func offerRecovery() {
        guard fileURL == nil, !isDirty, project.events.isEmpty, project.video == nil,
              let dir = Self.recoveryDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]),
              let newest = files.filter({ $0.pathExtension == ProjectStore.fileExtension }).max(by: {
                  let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  return a < b
              }),
              let recovered = try? store.load(from: newest) else { return }
        let alert = NSAlert()
        alert.messageText = "Recover unsaved project?"
        alert.informativeText = "“\(recovered.name)” was not saved. Recover it, or discard it."
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Discard")
        if alert.runModal() == .alertFirstButtonReturn {
            mutateQuietly { project = recovered }
            resetEditing()
            isDirty = true
            Task { await resolveVideo() }
        } else {
            try? FileManager.default.removeItem(at: newest)
        }
    }

    static var recoveryDirectory: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Feel/Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func mutateQuietly(_ body: () -> Void) {
        suppressDirty = true
        body()
        suppressDirty = false
    }

    // MARK: Video

    func importVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importVideo(url) }
    }

    func importVideo(_ url: URL) async {
        guard Self.videoExtensions.contains(url.pathExtension.lowercased()) else {
            errorMessage = "Unsupported file type. Use MP4, MOV or M4V."
            return
        }
        let started = url.startAccessingSecurityScopedResource()
        do {
            let meta = try await video.probe(url)
            // A different video replaces the haptics made for the old one. Undo brings them back.
            // A relink of a missing video keeps them: the state is then not loaded.
            let replacing = videoState == .loaded && activeVideoURL?.standardizedFileURL != url.standardizedFileURL
            releaseVideo()
            if replacing, !project.events.isEmpty {
                recordUndo()
                project.events = []
                selection = []
            }
            if started { scopedURL = url }
            project.video = VideoReference(url: url, bookmark: ProjectStore.makeBookmark(for: url), metadata: meta)
            if project.name == "Untitled" { project.name = url.deletingPathExtension().lastPathComponent }
            attach(url: url, duration: meta.duration)
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            errorMessage = "Cannot import video: \(error.localizedDescription)"
        }
    }

    func relinkVideoPanel() { importVideoPanel() }

    private func resolveVideo() async {
        guard let ref = project.video else { videoState = .none; return }
        let result = store.resolveVideo(ref)
        switch result.resolution {
        case .missing(let url):
            videoState = .missing(url)
        case .found(let url):
            let started = url.startAccessingSecurityScopedResource()
            do {
                let meta = try await video.probe(url)
                if started { scopedURL = url }
                if let fresh = result.refreshedBookmark {
                    mutateQuietly { project.video?.bookmark = fresh }
                }
                attach(url: url, duration: meta.duration)
            } catch {
                if started { url.stopAccessingSecurityScopedResource() }
                videoState = .failed(error.localizedDescription)
            }
        }
    }

    private func attach(url: URL, duration: Double) {
        activeVideoURL = url
        clearSuggestions()
        video.open(url, duration: duration)
        thumbs.load(url: url, duration: duration)
        waveform.load(url: url, duration: duration)
        videoState = .loaded
        session.setVideo(url)
        session.sendDuration(duration)
    }

    func setAutoRunning(_ on: Bool) { isAutoRunning = on }

    private func releaseVideo() {
        autoTask?.cancel()
        isAutoRunning = false
        spectrumCache = nil
        activeVideoURL = nil
        clearSuggestions()
        video.close()
        thumbs.clear()
        waveform.clear()
        session.setVideo(nil)
        session.sendDuration(0)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        videoState = .none
    }

    // MARK: Playback

    func togglePlay() { video.isPlaying ? pause() : play() }

    /// The iPhone is still getting the video. Playing now would leave it behind.
    var playBlocked: Bool {
        videoState == .loaded && session.isSyncing && session.videoBusy
    }

    func play() {
        guard videoState == .loaded, !playBlocked else { return }
        if session.isSyncing {
            if video.currentTime >= video.duration - 0.01 { video.seek(to: 0, precise: true) }
            let mediaStart = video.currentTime
            // Start both devices at one future instant. Lead covers preroll and network.
            let host = SharedClock.now() + 0.4
            video.play(atHostTime: host)
            session.sendPlay(mediaTime: mediaStart, hostTime: host, advance: project.settings.hapticAdvance)
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

    func step(frames: Int) {
        pause()
        video.step(frames: frames, frameRate: project.video?.metadata.frameRate ?? 30)
    }

    func setHapticAdvance(_ seconds: TimeInterval) {
        project.settings.hapticAdvance = min(max(seconds, -0.1), 0.3)
        if video.isPlaying, session.isSyncing { sendResync() }
    }

    /// While playing: restate the transport every 2 s so the iPhone corrects drift.
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
        // Sample media time and host time together.
        let host = SharedClock.now()
        let media = video.exactTime
        session.sendPlay(mediaTime: media, hostTime: host, advance: project.settings.hapticAdvance)
    }

    func audition(_ event: HapticEvent) { session.audition(event) }

    // MARK: Scrubbing

    func scrub(to time: TimelineTime) {
        if !isScrubbing {
            resumeAfterScrub = video.isPlaying
            if resumeAfterScrub { pause() }
            lastScrub = video.currentTime
        }
        isScrubbing = true
        video.seek(to: time, precise: false)
        // Feel events as the playhead crosses them.
        if let prev = lastScrub, time > prev, time - prev < 0.5 {
            for e in project.events where e.start > prev && e.start <= time { audition(e) }
        }
        lastScrub = time
    }

    func endScrub(at time: TimelineTime) {
        isScrubbing = false
        lastScrub = nil
        video.seek(to: time, precise: true)
        if resumeAfterScrub { resumeAfterScrub = false; play() } else { session.sendPause(mediaTime: time) }
    }
}
