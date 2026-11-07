// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import Foundation

/// Peak envelope of the first audio track. Mono 8 kHz decode, 100 buckets per second, values 0...1.
public enum AudioEnvelope {
    public static let bucketsPerSecond = 100.0

    /// nil when the file has no audio track or cannot be read.
    public static func extract(url: URL, duration: TimeInterval) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let sampleRate = 8000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let perBucket = Int(sampleRate / bucketsPerSecond)
        let total = max(Int((duration * bucketsPerSecond).rounded(.up)), 1)
        var peaks = [Float](repeating: 0, count: total)
        var index = 0, inBucket = 0
        var current: Int16 = 0

        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            for s in data {
                current = max(current, s == .min ? .max : abs(s))
                inBucket += 1
                if inBucket == perBucket {
                    if index < total { peaks[index] = Float(current) / Float(Int16.max) }
                    index += 1
                    inBucket = 0
                    current = 0
                }
            }
        }
        return index == 0 ? nil : peaks
    }
}
