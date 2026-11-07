// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import SoundAnalysis

/// Finds the time ranges that hold speech, with Apple's built-in sound classifier. Runs on the device.
/// When the classifier is not available the result is empty, and no audio is treated as speech.
public final class SpeechDetector {
    private final class Observer: NSObject, SNResultsObserving {
        private let lock = NSLock()
        private var found: [ClosedRange<Double>] = []

        var ranges: [ClosedRange<Double>] {
            lock.lock(); defer { lock.unlock() }
            return found
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let c = result as? SNClassificationResult,
                  let speech = c.classification(forIdentifier: "speech"),
                  speech.confidence >= SpeechDetector.minConfidence else { return }
            let start = c.timeRange.start.seconds
            let range = start...(start + c.timeRange.duration.seconds)
            lock.lock(); defer { lock.unlock() }
            found.append(range)
        }
    }

    static let minConfidence = 0.5
    /// The classifier window is about 1 s, wider than the speech it finds. Trim each side, so hits next to a line stay.
    static let trim = 0.2

    private let observer = Observer()
    private let format: AVAudioFormat?
    private let analyzer: SNAudioStreamAnalyzer?
    private var position: AVAudioFramePosition = 0

    /// `sampleRate`: rate of the mono samples given to `push`.
    public init(sampleRate: Double) {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        var analyzer: SNAudioStreamAnalyzer?
        if let format, let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            request.overlapFactor = 0.75
            let a = SNAudioStreamAnalyzer(format: format)
            if (try? a.add(request, withObserver: observer)) != nil { analyzer = a }
        }
        self.format = format
        self.analyzer = analyzer
    }

    public func push(_ samples: [Float]) {
        guard let analyzer, let format, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        analyzer.analyze(buffer, atAudioFramePosition: position)
        position += AVAudioFramePosition(samples.count)
    }

    /// Waits for the analysis to end. Returns sorted ranges that do not overlap.
    public func finish() -> [ClosedRange<Double>] {
        analyzer?.completeAnalysis()
        return Self.merged(observer.ranges, trim: Self.trim)
    }

    static func merged(_ ranges: [ClosedRange<Double>], trim: Double) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, r.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out.compactMap { r in
            let lo = r.lowerBound + trim, hi = r.upperBound - trim
            return lo < hi ? lo...hi : nil
        }
    }
}
