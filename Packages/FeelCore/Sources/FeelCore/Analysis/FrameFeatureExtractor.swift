// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import CoreVideo
import Foundation

/// Decodes video at low resolution and measures frames. Run off the main thread.
public enum FrameFeatureExtractor {
    public static let width = 160
    public static let height = 90
    /// Samples per second.
    public static let sampleRate = 15.0

    public enum ExtractError: Error { case noVideoTrack, cannotRead(String) }

    public static func extract(url: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> [FrameFeature] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExtractError.noVideoTrack }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ExtractError.cannotRead("Cannot read video track.") }
        reader.add(output)
        guard reader.startReading() else { throw ExtractError.cannotRead(reader.error?.localizedDescription ?? "Cannot start reading.") }

        var features: [FrameFeature] = []
        var prev: Frame?
        var lastT = -Double.infinity
        let step = 1 / sampleRate

        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard t - lastT >= step - 0.001, let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            lastT = t
            let frame = Frame(pixels)
            features.append(feature(t: t, frame, prev))
            prev = frame
            if duration > 0 { progress?(min(t / duration, 1)) }
        }
        if reader.status == .failed { throw ExtractError.cannotRead(reader.error?.localizedDescription ?? "Read failed.") }
        return features
    }

    // MARK: Measurement

    private struct Frame {
        var luma: [UInt8]
        var hist: [Double]
        var cols: [Double]
        var rows: [Double]
        var mean: Double
        var bright: Double

        init(_ buffer: CVPixelBuffer) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            var luma = [UInt8](repeating: 0, count: w * h)
            var hist = [Double](repeating: 0, count: 16)
            var cols = [Double](repeating: 0, count: w), rows = [Double](repeating: 0, count: h)
            var sum = 0.0, bright = 0.0
            if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                for y in 0..<h {
                    let row = base + y * stride
                    for x in 0..<w {
                        let b = Int(row[x * 4]), g = Int(row[x * 4 + 1]), r = Int(row[x * 4 + 2])
                        let l = (r * 77 + g * 150 + b * 29) >> 8
                        luma[y * w + x] = UInt8(l)
                        hist[l >> 4] += 1
                        cols[x] += Double(l)
                        rows[y] += Double(l)
                        sum += Double(l)
                        if l > 230 { bright += 1 }
                    }
                }
            }
            let n = Double(w * h)
            self.luma = luma
            self.hist = hist.map { $0 / n }
            self.cols = cols.map { $0 / Double(h) }
            self.rows = rows.map { $0 / Double(w) }
            self.mean = sum / n / 255
            self.bright = bright / n
        }
    }

    private static func feature(t: Double, _ f: Frame, _ p: Frame?) -> FrameFeature {
        guard let p else { return FrameFeature(t: t, luma: f.mean, bright: f.bright) }
        var diff = 0.0
        for i in 0..<f.luma.count { diff += abs(Double(f.luma[i]) - Double(p.luma[i])) }
        let motion = diff / Double(f.luma.count) / 255
        let histDiff = 0.5 * zip(f.hist, p.hist).reduce(0) { $0 + abs($1.0 - $1.1) }
        return FrameFeature(
            t: t, luma: f.mean, histDiff: histDiff, motion: motion,
            shiftX: shift(f.cols, p.cols), shiftY: shift(f.rows, p.rows), bright: f.bright
        )
    }

    /// Best 1-D shift (pixels) between two projections, by sum of absolute differences.
    private static func shift(_ a: [Double], _ b: [Double], maxLag: Int = 8) -> Double {
        var best = 0, bestCost = Double.infinity
        for lag in -maxLag...maxLag {
            var cost = 0.0, n = 0
            for i in max(0, lag)..<min(a.count, a.count + lag) {
                cost += abs(a[i] - b[i - lag])
                n += 1
            }
            cost /= Double(max(n, 1))
            if cost < bestCost - 1e-9 { bestCost = cost; best = lag }
        }
        return Double(best)
    }
}

/// Ties extraction and suggestion together. Cache `input` to re-run suggestions when sensitivity changes.
public struct VideoAnalyzer: Sendable {
    public var suggester: HapticSuggester

    public init(suggester: HapticSuggester = HeuristicSuggester()) { self.suggester = suggester }

    public func measure(url: URL, duration: TimelineTime, progress: (@Sendable (Double) -> Void)? = nil) async throws -> AnalysisInput {
        async let audio = AudioEnvelope.extract(url: url, duration: duration)
        let features = try await FrameFeatureExtractor.extract(url: url, progress: progress)
        return AnalysisInput(features: features, audio: await audio ?? [], duration: duration)
    }
}
