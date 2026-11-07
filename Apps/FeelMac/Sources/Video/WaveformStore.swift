// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import Foundation
import Observation

/// Peak envelope of the first audio track. Read async, mono 8 kHz, 100 buckets per second.
@MainActor @Observable
final class WaveformStore {
    enum State: Equatable { case idle, loading, ready, noAudio }

    static let bucketsPerSecond = AudioEnvelope.bucketsPerSecond

    private(set) var peaks: [Float] = []
    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: [Float]] = [:]

    func clear() {
        task?.cancel()
        peaks = []
        state = .idle
    }

    func load(url: URL, duration: Double) {
        task?.cancel()
        let key = "\(url.path)|\(duration)"
        if let hit = cache[key] {
            peaks = hit
            state = .ready
            return
        }
        peaks = []
        state = .loading
        task = Task { [weak self] in
            let result = await AudioEnvelope.extract(url: url, duration: duration)
            guard !Task.isCancelled, let self else { return }
            if let result, !result.isEmpty {
                self.cache[key] = result
                self.peaks = result
                self.state = .ready
            } else {
                self.state = .noAudio
            }
        }
    }
}
