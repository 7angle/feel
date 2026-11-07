// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import AppKit
import Observation

/// Async thumbnail strip generation with in-memory cache per video.
@MainActor @Observable
final class ThumbnailStore {
    struct Strip {
        var spacing: Double
        var images: [Int: CGImage]
    }

    private(set) var strip = Strip(spacing: 1, images: [:])
    @ObservationIgnored private var cache: [String: Strip] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    func clear() {
        task?.cancel()
        strip = Strip(spacing: 1, images: [:])
    }

    func load(url: URL, duration: Double) {
        task?.cancel()
        let key = "\(url.path)|\(duration)"
        if let hit = cache[key], !hit.images.isEmpty {
            strip = hit
            return
        }
        guard duration > 0 else { clear(); return }
        let count = min(max(Int(duration.rounded(.up)), 8), 240)
        let spacing = duration / Double(count)
        strip = Strip(spacing: spacing, images: [:])
        task = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 320, height: 180)
            gen.requestedTimeToleranceBefore = .positiveInfinity
            gen.requestedTimeToleranceAfter = .positiveInfinity
            let times = (0..<count).map { CMTime(seconds: (Double($0) + 0.5) * spacing, preferredTimescale: 600) }
            for await result in gen.images(for: times) {
                if Task.isCancelled { return }
                guard let image = try? result.image, let idx = times.firstIndex(of: result.requestedTime) else { continue }
                await MainActor.run {
                    guard let self else { return }
                    self.strip.images[idx] = image
                    self.cache[key] = self.strip
                }
            }
        }
    }
}
