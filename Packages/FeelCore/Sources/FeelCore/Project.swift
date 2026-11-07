// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public struct VideoMetadata: Codable, Equatable, Sendable {
    public var duration: TimelineTime
    public var frameRate: Double
    public var width: Int
    public var height: Int

    public init(duration: TimelineTime, frameRate: Double, width: Int, height: Int) {
        self.duration = duration
        self.frameRate = frameRate
        self.width = width
        self.height = height
    }

    public var resolutionLabel: String { "\(width)×\(height)" }
}

/// Reference to video on disk. Never embeds video data.
public struct VideoReference: Codable, Equatable, Sendable {
    public var url: URL
    /// Security-scoped bookmark. Survives file moves/renames.
    public var bookmark: Data?
    public var metadata: VideoMetadata

    public init(url: URL, bookmark: Data?, metadata: VideoMetadata) {
        self.url = url
        self.bookmark = bookmark
        self.metadata = metadata
    }
}

public struct TimelineSettings: Codable, Equatable, Sendable {
    /// Points per second.
    public var zoom: Double
    public var scroll: Double

    public init(zoom: Double = 80, scroll: Double = 0) {
        self.zoom = zoom
        self.scroll = scroll
    }
}

public struct ProjectSettings: Codable, Equatable, Sendable {
    public var snapToGrid: Bool
    public var gridInterval: TimelineTime
    public var autosave: Bool
    /// Seconds to fire haptics early on the iPhone. Compensates engine and display latency.
    public var hapticAdvance: TimeInterval

    public init(snapToGrid: Bool = true, gridInterval: TimelineTime = 0.05, autosave: Bool = true, hapticAdvance: TimeInterval = 0) {
        self.snapToGrid = snapToGrid
        self.gridInterval = gridInterval
        self.autosave = autosave
        self.hapticAdvance = hapticAdvance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        gridInterval = try c.decodeIfPresent(TimelineTime.self, forKey: .gridInterval) ?? 0.05
        autosave = try c.decodeIfPresent(Bool.self, forKey: .autosave) ?? true
        hapticAdvance = try c.decodeIfPresent(TimeInterval.self, forKey: .hapticAdvance) ?? 0
    }
}

public struct HapticProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var name: String
    public var created: Date
    public var modified: Date
    public var video: VideoReference?
    public var events: [HapticEvent]
    public var customPresets: [HapticPreset]
    public var timeline: TimelineSettings
    public var settings: ProjectSettings

    public init(
        id: UUID = UUID(),
        name: String = "Untitled",
        created: Date = Date(),
        modified: Date = Date(),
        video: VideoReference? = nil,
        events: [HapticEvent] = [],
        customPresets: [HapticPreset] = [],
        timeline: TimelineSettings = .init(),
        settings: ProjectSettings = .init()
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.name = name
        self.created = created
        self.modified = modified
        self.video = video
        self.events = events
        self.customPresets = customPresets
        self.timeline = timeline
        self.settings = settings
    }

    public var duration: TimelineTime { video?.metadata.duration ?? 0 }
}

public enum ProjectCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ p: HapticProject) throws -> Data { try encoder().encode(p) }
    public static func decode(_ data: Data) throws -> HapticProject { try decoder().decode(HapticProject.self, from: data) }
}
