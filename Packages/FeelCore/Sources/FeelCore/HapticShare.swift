// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public enum HapticShareError: Error, Equatable, LocalizedError {
    case notHapticFile
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notHapticFile: "This file is not a Feel haptics file."
        case .unsupportedVersion: "This haptics file is from a newer version of Feel."
        }
    }
}

/// Reads haptics files made by the editor (JSON export). Holds no video data.
public enum HapticShare {
    public static let fileExtension = "json"
    public static let supportedVersion = 1

    public enum Match: Equatable, Sendable {
        /// Same length and size as the video the haptics were made for.
        case match
        /// The file names a video of another length. Timing will be off.
        case lengthDiffers(expected: TimelineTime, actual: TimelineTime)
        /// The file does not say which video it is for.
        case unknown
    }

    public static func decode(_ data: Data) throws -> HapticExportDocument {
        guard let doc = try? ProjectCoding.decoder().decode(HapticExportDocument.self, from: data),
              doc.format == "feel-haptics" else { throw HapticShareError.notHapticFile }
        guard doc.version <= supportedVersion else { throw HapticShareError.unsupportedVersion(doc.version) }
        return doc
    }

    public static func load(from url: URL) throws -> HapticExportDocument {
        try decode(Data(contentsOf: url))
    }

    /// Events with fresh IDs, sorted by start. Safe to add to a project more than once.
    public static func events(from doc: HapticExportDocument) -> [HapticEvent] {
        doc.events.sorted { $0.start < $1.start }.map { e in
            HapticEvent(
                type: e.type, start: e.start, duration: e.duration, intensity: e.intensity, sharpness: e.sharpness,
                repetitionInterval: e.repetitionInterval, repetitionCount: e.repetitionCount,
                fadeIn: e.fadeIn, fadeOut: e.fadeOut,
                intensityCurve: e.intensityCurve, sharpnessCurve: e.sharpnessCurve, presetID: e.presetID
            )
        }
    }

    /// Compare the file with the video the user opened. Tolerance in seconds.
    public static func match(_ doc: HapticExportDocument, video: VideoMetadata, tolerance: TimelineTime = 0.5) -> Match {
        guard let expected = doc.video else { return .unknown }
        if abs(expected.duration - video.duration) <= tolerance { return .match }
        return .lengthDiffers(expected: expected.duration, actual: video.duration)
    }
}
