// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public enum FeelProtocol {
    public static let version = 1
    public static let bonjourType = "_feelhaptics._tcp"
    /// Bonjour TXT key and value that mark an advertiser as a Mac editor.
    public static let roleKey = "role"
    public static let editorRole = "editor"
}

public struct Hello: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case editor, companion }
    public var name: String
    public var role: Role
    public var protocolVersion: Int
    public var supportsHaptics: Bool

    public init(name: String, role: Role, supportsHaptics: Bool, protocolVersion: Int = FeelProtocol.version) {
        self.name = name
        self.role = role
        self.supportsHaptics = supportsHaptics
        self.protocolVersion = protocolVersion
    }
}

public struct CompanionStatus: Codable, Equatable, Sendable {
    public var playing: Bool
    public var engineReady: Bool
    /// Round trip to editor in seconds, if measured.
    public var rtt: Double?
    public var message: String?

    public init(playing: Bool, engineReady: Bool, rtt: Double? = nil, message: String? = nil) {
        self.playing = playing
        self.engineReady = engineReady
        self.rtt = rtt
        self.message = message
    }
}

/// Wire messages. One JSON object per line (newline-delimited).
public enum Message: Codable, Equatable, Sendable {
    case hello(Hello)
    /// Companion → editor. t0 = companion clock at send.
    case ping(id: Int, t0: Double)
    /// Editor → companion. t1/t2 = editor clock at receive/send.
    case pong(id: Int, t0: Double, t1: Double, t2: Double)
    /// Full state sync. Latest revision wins.
    case pattern(revision: Int, events: [HapticEvent])
    /// Media time `mediaTime` plays at editor host-clock time `hostTime`. Re-sent periodically for drift.
    case play(mediaTime: Double, hostTime: Double, advance: Double)
    case pause(mediaTime: Double)
    /// Play one event now (editing feedback).
    case audition(HapticEvent)
    case status(CompanionStatus)
    /// Editor → companion. A video file follows as chunks, in order. A new offer replaces the old one.
    case videoOffer(id: String, name: String, size: Int)
    case videoChunk(id: String, offset: Int, data: Data)
    case videoEnd(id: String)
    /// Companion → editor.
    case videoReady(id: String)
    case videoFailed(id: String, reason: String)
    /// Editor → companion. Drop the video.
    case videoClear
    /// Editor → companion. Length of the timeline, seconds. 0 = no video.
    case timeline(duration: Double)
    /// Companion → editor. Remote control from the iPhone.
    case remotePlay
    case remotePause
    /// `final` false while the finger drags. true on release.
    case remoteSeek(mediaTime: Double, final: Bool)
    case bye

    public func encoded() throws -> Data {
        var d = try JSONEncoder().encode(self)
        d.append(0x0A)
        return d
    }

    public static func decode(_ line: Data) throws -> Message {
        try JSONDecoder().decode(Message.self, from: line)
    }
}
