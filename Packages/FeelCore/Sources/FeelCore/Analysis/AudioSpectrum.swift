// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Accelerate
import AVFoundation
import Foundation

/// Per-band loudness and change, 100 values per second. Index i covers audio from i/100 s.
public struct AudioSpectrum: Sendable, Equatable {
    public static let rate = 100.0
    /// Band energy, log-compressed, 0...~1.
    public var bass: [Float] = []   //  30 - 190 Hz
    public var mid: [Float] = []    // 190 - 2000 Hz
    public var high: [Float] = []   //   2 - 8 kHz
    /// Spectral flux: how much new energy appeared in the band since the last hop.
    public var fluxBass: [Float] = []
    public var fluxMid: [Float] = []
    public var fluxHigh: [Float] = []
    /// Seconds that hold speech. Empty when none was found or the classifier did not run.
    public var speech: [ClosedRange<Double>] = []

    public init() {}

    public var count: Int { bass.count }
    public var duration: TimeInterval { Double(count) / Self.rate }
}

/// STFT with a 512-sample Hann window at 16 kHz, hop 160 samples (10 ms).
public final class SpectrumAnalyzer {
    public static let sampleRate = 16_000.0
    static let frame = 512
    static let hop = 160

    private let setup: FFTSetup
    private let log2n = vDSP_Length(9)
    private var window = [Float](repeating: 0, count: SpectrumAnalyzer.frame)
    private var pending: [Float] = []
    private var prevLog = [Float](repeating: 0, count: SpectrumAnalyzer.frame / 2)
    private var havePrev = false
    public private(set) var result = AudioSpectrum()

    // Bin k = k * 31.25 Hz.
    private let bassBins = 1...6
    private let midBins = 7...64
    private let highBins = 65...255

    public init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.frame), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feed mono samples at 16 kHz, -1...1.
    public func push(_ samples: [Float]) {
        pending.append(contentsOf: samples)
        var pos = 0
        while pending.count - pos >= Self.frame {
            process(pending, at: pos)
            pos += Self.hop
        }
        if pos > 0 { pending.removeFirst(min(pos, pending.count)) }
    }

    private func process(_ x: [Float], at start: Int) {
        let n = Self.frame, half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        x.withUnsafeBufferPointer { src in
            vDSP_vmul(src.baseAddress! + start, 1, window, 1, &windowed, 1, vDSP_Length(n))
        }
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        power[0] = 0 // DC and Nyquist share bin 0 in packed output.

        var logs = [Float](repeating: 0, count: half)
        for k in 1..<half { logs[k] = log1p(power[k].squareRoot() * 0.05) }

        func band(_ bins: ClosedRange<Int>) -> (level: Float, flux: Float) {
            var sum: Float = 0, flux: Float = 0
            for k in bins {
                sum += logs[k]
                if havePrev { flux += max(0, logs[k] - prevLog[k]) }
            }
            let c = Float(bins.count)
            return (sum / c, flux / c)
        }
        let b = band(bassBins), m = band(midBins), h = band(highBins)
        result.bass.append(b.level); result.fluxBass.append(b.flux)
        result.mid.append(m.level); result.fluxMid.append(m.flux)
        result.high.append(h.level); result.fluxHigh.append(h.flux)
        prevLog = logs
        havePrev = true
    }

    /// Whole signal in one call.
    public static func analyze(_ samples: [Float]) -> AudioSpectrum {
        let a = SpectrumAnalyzer()
        a.push(samples)
        return a.result
    }
}

public enum AudioSpectrumExtractor {
    /// nil when the file has no audio or cannot be read.
    public static func extract(url: URL) async -> AudioSpectrum? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: SpectrumAnalyzer.sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let analyzer = SpectrumAnalyzer()
        let speech = SpeechDetector(sampleRate: SpectrumAnalyzer.sampleRate)
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            let samples = data.map { Float($0) / 32768 }
            analyzer.push(samples)
            speech.push(samples)
        }
        guard analyzer.result.count > 0 else { return nil }
        var result = analyzer.result
        result.speech = speech.finish()
        return result
    }
}
