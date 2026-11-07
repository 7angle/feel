// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public struct ExportIssue: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case ahap, json, swift

    public var title: String {
        switch self {
        case .ahap: "AHAP"
        case .json: "JSON"
        case .swift: "Swift playback code"
        }
    }
}

/// Document written by JSON export.
public struct HapticExportDocument: Codable, Equatable, Sendable {
    public struct Video: Codable, Equatable, Sendable {
        public var fileName: String
        public var duration: TimelineTime
        public var frameRate: Double
        public var width: Int
        public var height: Int
    }

    public struct Event: Codable, Equatable, Sendable {
        public var id: UUID
        public var type: HapticEventType
        public var start: TimelineTime
        public var duration: TimelineTime
        public var intensity: Double
        public var sharpness: Double
        public var repetitionInterval: TimelineTime
        public var repetitionCount: Int
        public var fadeIn: TimelineTime
        public var fadeOut: TimelineTime
        public var intensityCurve: [CurvePoint]
        public var sharpnessCurve: [CurvePoint]
        public var presetID: String?
        public var presetName: String?
    }

    public var format = "feel-haptics"
    public var version = 1
    public var projectName: String
    public var exported: Date
    public var video: Video?
    public var timelineDuration: TimelineTime
    public var events: [Event]
    /// Presets referenced by events.
    public var presets: [HapticPreset]
}

public enum ExportEngine {
    // MARK: Validation

    public static func validate(_ project: HapticProject) -> [ExportIssue] {
        var out: [ExportIssue] = []
        if project.events.isEmpty { out.append(ExportIssue(.error, "No haptic events to export.")) }
        let dur = project.duration
        for e in project.events {
            let vals = [e.start, e.duration, e.intensity, e.sharpness, e.repetitionInterval, e.fadeIn, e.fadeOut]
            if vals.contains(where: { !$0.isFinite }) {
                out.append(ExportIssue(.error, "Event at \(Timebase.format(e.start)) has an invalid number."))
            }
        }
        if dur > 0 {
            let late = project.events.filter { $0.start > dur }.count
            if late > 0 { out.append(ExportIssue(.warning, "\(late) event(s) start after the video ends.")) }
            let over = project.events.filter { $0.start <= dur && $0.end > dur + 0.001 }.count
            if over > 0 { out.append(ExportIssue(.warning, "\(over) event(s) run past the video end.")) }
        }
        let silent = project.events.filter { $0.intensity <= 0 }.count
        if silent > 0 { out.append(ExportIssue(.warning, "\(silent) event(s) have zero intensity.")) }
        if project.video == nil { out.append(ExportIssue(.warning, "No video linked. Video metadata will be empty.")) }
        return out
    }

    public static func hasErrors(_ issues: [ExportIssue]) -> Bool { issues.contains { $0.severity == .error } }

    // MARK: Formats

    public static func ahap(_ project: HapticProject) throws -> Data {
        try AHAPBuilder.data(events: project.events, description: "\(project.name) — exported from Feel")
    }

    public static func document(_ project: HapticProject, now: Date = Date()) -> HapticExportDocument {
        let all = HapticPresetLibrary.all(custom: project.customPresets)
        let used = Set(project.events.compactMap(\.presetID))
        let events = project.events.sorted { $0.start < $1.start }.map { e in
            HapticExportDocument.Event(
                id: e.id, type: e.type, start: e.start, duration: e.duration, intensity: e.intensity, sharpness: e.sharpness,
                repetitionInterval: e.repetitionInterval, repetitionCount: e.repetitionCount, fadeIn: e.fadeIn, fadeOut: e.fadeOut,
                intensityCurve: e.intensityCurve, sharpnessCurve: e.sharpnessCurve, presetID: e.presetID,
                presetName: e.presetID.flatMap { id in all.first { $0.id == id }?.name }
            )
        }
        let video = project.video.map {
            HapticExportDocument.Video(
                fileName: $0.url.lastPathComponent, duration: $0.metadata.duration, frameRate: $0.metadata.frameRate,
                width: $0.metadata.width, height: $0.metadata.height
            )
        }
        return HapticExportDocument(
            projectName: project.name, exported: now, video: video, timelineDuration: project.duration,
            events: events, presets: all.filter { used.contains($0.id) }
        )
    }

    public static func json(_ project: HapticProject, now: Date = Date()) throws -> Data {
        try ProjectCoding.encoder().encode(document(project, now: now))
    }

    /// Safe file stem from project name.
    public static func fileStem(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return s.isEmpty ? "FeelHaptics" : s
    }

    /// Writes selected formats into `directory`. Returns written URLs. Throws on validation errors.
    @discardableResult
    public static func write(_ project: HapticProject, formats: Set<ExportFormat>, to directory: URL) throws -> [URL] {
        let issues = validate(project)
        if hasErrors(issues) { throw ExportError.validation(issues.filter { $0.severity == .error }.map(\.message)) }
        let stem = fileStem(project.name)
        var written: [URL] = []
        func put(_ data: Data, _ name: String) throws {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            written.append(url)
        }
        if formats.contains(.ahap) || formats.contains(.swift) { try put(try ahap(project), "\(stem).ahap") }
        if formats.contains(.json) { try put(try json(project), "\(stem).json") }
        if formats.contains(.swift) { try put(Data(SwiftPlaybackTemplate.source(ahapName: stem).utf8), "FeelHapticVideoSync.swift") }
        return written
    }
}

public enum ExportError: Error, Equatable, LocalizedError {
    case validation([String])

    public var errorDescription: String? {
        switch self {
        case .validation(let m): m.joined(separator: "\n")
        }
    }
}
