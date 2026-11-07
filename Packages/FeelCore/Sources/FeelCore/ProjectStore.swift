// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import Foundation

public enum ProjectStoreError: Error, Equatable {
    case unsupportedVersion(Int)
}

public enum VideoResolution: Equatable, Sendable {
    case found(URL)
    case missing(lastKnown: URL)
}

/// File-based project persistence. Atomic writes. Pure Foundation.
public struct ProjectStore: Sendable {
    public static let fileExtension = "feelproj"

    public init() {}

    public func save(_ project: HapticProject, to url: URL) throws {
        var p = project
        p.modified = Date()
        let data = try ProjectCoding.encode(p)
        do { try data.write(to: url, options: .atomic) }
        catch { try data.write(to: url) } // sandbox may block temp file beside target
    }

    public func load(from url: URL) throws -> HapticProject {
        let data = try Data(contentsOf: url)
        let p = try ProjectCoding.decode(data)
        guard p.version <= HapticProject.currentVersion else {
            throw ProjectStoreError.unsupportedVersion(p.version)
        }
        return p
    }

    /// New project with new ID and name, same content.
    public func duplicate(_ project: HapticProject, name: String) -> HapticProject {
        var p = project
        p.id = UUID()
        p.name = name
        p.created = Date()
        p.modified = Date()
        return p
    }

    /// Resolve video: bookmark first (handles moves), then stored URL.
    /// Caller must call `stopAccessingSecurityScopedResource` when done if bookmark scope used.
    public func resolveVideo(_ ref: VideoReference) -> (resolution: VideoResolution, refreshedBookmark: Data?) {
        if let data = ref.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: Self.resolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                return (.found(url), stale ? Self.makeBookmark(for: url) : nil)
            }
        }
        if FileManager.default.fileExists(atPath: ref.url.path) { return (.found(ref.url), nil) }
        return (.missing(lastKnown: ref.url), nil)
    }

    public static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: createOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    #if os(macOS)
    static let createOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let createOptions: URL.BookmarkCreationOptions = []
    static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif
}
