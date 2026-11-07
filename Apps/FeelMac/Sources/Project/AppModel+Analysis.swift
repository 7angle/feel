// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import Foundation

extension AppModel {
    var visibleSuggestions: [HapticSuggestion] { suggestions.filter { shownKinds.contains($0.kind) } }

    func runAnalysis() {
        guard let url = activeVideoURL, case .loaded = videoState else { return }
        analysisTask?.cancel()
        analysisState = .running(0)
        let duration = project.duration
        let analyzer = analyzer
        analysisTask = Task { [weak self] in
            do {
                let input = try await Task.detached(priority: .utility) {
                    try await analyzer.measure(url: url, duration: duration) { p in
                        Task { @MainActor in self?.analysisProgress(p) }
                    }
                }.value
                guard !Task.isCancelled, let self else { return }
                self.analysisInput = input
                self.analysisState = .done
                self.rerunSuggester()
            } catch is CancellationError {
                self?.analysisState = .idle
            } catch {
                self?.analysisState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisState = .idle
    }

    private func analysisProgress(_ p: Double) {
        if case .running = analysisState { analysisState = .running(p) }
    }

    /// Cheap. Runs again when sensitivity changes without decoding the video again.
    func rerunSuggester() {
        guard let input = analysisInput else { return }
        suggestions = analyzer.suggester.suggest(input, sensitivity: sensitivity)
    }

    func clearSuggestions() {
        analysisTask?.cancel()
        analysisInput = nil
        suggestions = []
        analysisState = .idle
    }

    func toggleKind(_ kind: SuggestionKind) {
        if shownKinds.contains(kind) { shownKinds.remove(kind) } else { shownKinds.insert(kind) }
    }

    func accept(_ suggestion: HapticSuggestion) {
        recordUndo()
        var events = suggestion.events
        for i in events.indices { events[i].id = UUID() }
        project.events.append(contentsOf: events)
        selection = Set(events.map(\.id))
        suggestions.removeAll { $0.id == suggestion.id }
        for e in events { audition(e) }
    }

    func acceptAllVisible() {
        let list = visibleSuggestions
        guard !list.isEmpty else { return }
        recordUndo()
        var added: [HapticEvent] = []
        for s in list {
            for var e in s.events { e.id = UUID(); added.append(e) }
        }
        project.events.append(contentsOf: added)
        selection = Set(added.map(\.id))
        let ids = Set(list.map(\.id))
        suggestions.removeAll { ids.contains($0.id) }
    }

    func reject(_ suggestion: HapticSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func rejectAllVisible() {
        let ids = Set(visibleSuggestions.map(\.id))
        suggestions.removeAll { ids.contains($0.id) }
    }

    /// Jump to a suggestion and feel it.
    func preview(_ suggestion: HapticSuggestion) {
        video.seek(to: max(suggestion.time - 0.5, 0), precise: true)
        if let first = suggestion.events.first { audition(first) }
    }
}
