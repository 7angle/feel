// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import FeelCore
import SwiftUI

extension AppModel {
    // MARK: History

    /// Record state before a change. Same `key` within 1s merges into one undo step.
    func recordUndo(key: String? = nil) {
        let now = Date()
        if let key, key == lastEditKey, now.timeIntervalSince(lastEditTime) < 1 {
            lastEditTime = now
            return
        }
        history.record(project.events)
        lastEditKey = key
        lastEditTime = now
        refreshHistoryFlags()
    }

    func undo() {
        guard let prev = history.undo(current: project.events) else { return }
        applyHistory(prev)
    }

    func redo() {
        guard let next = history.redo(current: project.events) else { return }
        applyHistory(next)
    }

    private func applyHistory(_ events: [HapticEvent]) {
        project.events = events
        selection = selection.intersection(Set(events.map(\.id)))
        lastEditKey = nil
        refreshHistoryFlags()
    }

    private func refreshHistoryFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: Selection

    func select(_ id: UUID, extend: Bool) {
        lastEditKey = nil
        if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if !selection.contains(id) {
            selection = [id]
        }
    }

    func selectAll() { selection = Set(project.events.map(\.id)) }
    func clearSelection() { selection = []; lastEditKey = nil }

    var selectedEvents: [HapticEvent] { project.events.filter { selection.contains($0.id) } }
    var gridInterval: TimelineTime? { project.settings.snapToGrid ? project.settings.gridInterval : nil }

    // MARK: Add / remove

    func addEvent(_ type: HapticEventType, at time: TimelineTime? = nil) {
        recordUndo()
        let e = EventEditing.defaultEvent(type, at: EventEditing.snap(time ?? video.currentTime, grid: gridInterval))
        project.events.append(e)
        selection = [e.id]
        audition(e)
    }

    func insert(_ preset: HapticPreset, at time: TimelineTime? = nil) {
        recordUndo()
        let new = preset.instantiate(at: EventEditing.snap(time ?? video.currentTime, grid: gridInterval))
        project.events.append(contentsOf: new)
        selection = Set(new.map(\.id))
        audition(sequence: new)
    }

    /// Play events on connected phones with their real spacing. Changes nothing in the project.
    func audition(sequence events: [HapticEvent]) {
        auditionTask?.cancel()
        let ordered = events.sorted { $0.start < $1.start }
        guard let origin = ordered.first?.start else { return }
        auditionTask = Task { [weak self] in
            var elapsed = 0.0
            for e in ordered {
                let wait = e.start - origin - elapsed
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    elapsed += wait
                }
                guard !Task.isCancelled else { return }
                self?.audition(e)
            }
        }
    }

    /// A Library item dropped on the timeline.
    func dropLibraryItem(_ payload: String, at time: TimelineTime) -> Bool {
        guard let item = LibraryItem(payload: payload) else { return false }
        switch item {
        case .type(let type): addEvent(type, at: time)
        case .preset(let id):
            guard let preset = allPresets.first(where: { $0.id == id }) else { return false }
            insert(preset, at: time)
        }
        return true
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        recordUndo()
        project.events.removeAll { selection.contains($0.id) }
        selection = []
    }

    func duplicateSelection() {
        let copies = EventEditing.duplicate(selectedEvents)
        guard !copies.isEmpty else { return }
        recordUndo()
        project.events.append(contentsOf: copies)
        selection = Set(copies.map(\.id))
    }

    // MARK: Move / resize

    func beginMove() {
        moveOrigins = Dictionary(uniqueKeysWithValues: selectedEvents.map { ($0.id, $0.start) })
        moveRecorded = false
    }

    func updateMove(delta: TimelineTime, anchor: UUID) {
        guard !moveOrigins.isEmpty else { return }
        if !moveRecorded {
            guard abs(delta) > 0.001 else { return }
            recordUndo()
            moveRecorded = true
        }
        var events = project.events
        EventEditing.move(&events, origins: moveOrigins, delta: delta, anchor: anchor, grid: gridInterval, duration: project.duration)
        project.events = events
    }

    func endMove() {
        if moveRecorded, let e = selectedEvents.first { audition(e) }
        moveOrigins = [:]
        moveRecorded = false
        lastEditKey = nil
    }

    func resize(_ id: UUID, edge: EventEditing.ResizeEdge, to time: TimelineTime) {
        guard let i = project.events.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(key: "resize-\(id)")
        project.events[i] = EventEditing.resized(project.events[i], edge: edge, to: time, grid: gridInterval, limit: project.duration)
    }

    // MARK: Auto from audio

    var canAutoFromAudio: Bool { videoState == .loaded && waveform.state != .noAudio && !isAutoRunning }

    /// Adds events found in the audio. They replace the events of an earlier run, except the ones
    /// the user edited. Other events stay. One undo step.
    func autoHapticsFromAudio() {
        guard canAutoFromAudio, let url = activeVideoURL else { return }
        autoTask?.cancel()
        setAutoRunning(true)
        let cached = spectrumCache?.url == url ? spectrumCache?.spectrum : nil
        autoTask = Task { [weak self] in
            let spectrum: AudioSpectrum?
            if let cached { spectrum = cached } else {
                spectrum = await Task.detached(priority: .userInitiated) { await AudioSpectrumExtractor.extract(url: url) }.value
            }
            guard !Task.isCancelled, let self else { return }
            self.setAutoRunning(false)
            guard let spectrum else {
                self.errorMessage = "Cannot read the audio of this video."
                return
            }
            self.spectrumCache = (url, spectrum)
            let found = AudioHaptics.generate(spectrum: spectrum, sensitivity: self.sensitivity)
            guard !found.isEmpty else {
                self.errorMessage = "No clear hits in the audio. Raise sensitivity in the Suggestions tab, then try again."
                return
            }
            self.recordUndo()
            var events = self.project.events.filter { $0.generatedBy != AudioHaptics.generatorID }
            events.append(contentsOf: found)
            self.project.events = events
            self.selection = Set(found.map(\.id))
        }
    }

    func deleteAllEvents() {
        guard !project.events.isEmpty else { return }
        recordUndo()
        project.events = []
        selection = []
    }

    // MARK: Inspector

    func binding(for id: UUID) -> Binding<HapticEvent> {
        Binding(
            get: { self.project.events.first { $0.id == id } ?? HapticEvent(type: .tap, start: 0) },
            set: { new in
                guard let i = self.project.events.firstIndex(where: { $0.id == id }) else { return }
                self.recordUndo(key: "inspector-\(id)")
                var n = new.normalized()
                n.generatedBy = nil
                if n.type == .rumble, n.duration < 0.05 { n.duration = 0.5 }
                self.project.events[i] = n
                self.scheduleAudition(n)
            }
        )
    }

    /// Edits via sliders fire many sets. Feel the result once the value settles.
    private func scheduleAudition(_ e: HapticEvent) {
        auditionTask?.cancel()
        auditionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.audition(e)
        }
    }

    // MARK: Presets

    var allPresets: [HapticPreset] { HapticPresetLibrary.all(custom: project.customPresets) }

    func saveSelectionAsPreset() {
        guard !selection.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Save preset"
        alert.informativeText = "Name for the new preset."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "My Preset"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let preset = EventEditing.makePreset(id: "custom-\(UUID().uuidString)", name: name, from: selectedEvents) else { return }
        project.customPresets.append(preset)
    }

    func deleteCustomPreset(_ id: String) {
        project.customPresets.removeAll { $0.id == id }
    }
}

/// What a drag from the Library carries.
enum LibraryItem {
    case type(HapticEventType)
    case preset(String)

    private static let typePrefix = "feel.type:"
    private static let presetPrefix = "feel.preset:"

    var payload: String {
        switch self {
        case .type(let t): Self.typePrefix + t.rawValue
        case .preset(let id): Self.presetPrefix + id
        }
    }

    init?(payload: String) {
        if payload.hasPrefix(Self.typePrefix), let t = HapticEventType(rawValue: String(payload.dropFirst(Self.typePrefix.count))) {
            self = .type(t)
        } else if payload.hasPrefix(Self.presetPrefix) {
            self = .preset(String(payload.dropFirst(Self.presetPrefix.count)))
        } else {
            return nil
        }
    }
}
