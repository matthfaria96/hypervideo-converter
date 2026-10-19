import Foundation

/// Bookmarks that keep persisted file references valid across relaunches and moves.
/// Inside the App Sandbox they carry a security scope; otherwise they're plain bookmarks.
public enum FileBookmarks {
    /// True when the process runs inside the App Sandbox.
    public static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    public static func make(for url: URL, securityScoped: Bool = isSandboxed) -> Data? {
        try? url.bookmarkData(
            options: securityScoped ? [.withSecurityScope] : [],
            includingResourceValuesForKeys: nil, relativeTo: nil
        )
    }

    public struct Resolved: Sendable {
        public var url: URL
        /// A fresh bookmark when the stored one was stale, nil when it's still current.
        public var refreshed: Data?
    }

    /// Resolves `data` to the file's current location, nil when the file is gone.
    public static func resolve(_ data: Data, securityScoped: Bool = isSandboxed) -> Resolved? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: securityScoped ? [.withSecurityScope, .withoutUI] : [.withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale
        ), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Resolved(url: url, refreshed: stale ? make(for: url, securityScoped: securityScoped) : nil)
    }

    /// Starts security-scoped access to `urls`; pass the result to `stopAccessing`.
    public static func startAccessing(_ urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    public static func stopAccessing(_ urls: [URL]) {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}

extension EncodeJob {
    /// Source, destination folder and subtitle files the encode reads or writes.
    public var accessedURLs: [URL] {
        [source, destination.deletingLastPathComponent()] + (subtitleFiles ?? []).map(\.url)
    }

    /// A copy with bookmarks for the source, destination folder and subtitle files.
    public func bookmarked(securityScoped: Bool = FileBookmarks.isSandboxed) -> EncodeJob {
        var copy = self
        copy.sourceBookmark = sourceBookmark ?? FileBookmarks.make(for: source, securityScoped: securityScoped)
        copy.destinationFolderBookmark = destinationFolderBookmark
            ?? FileBookmarks.make(for: destination.deletingLastPathComponent(), securityScoped: securityScoped)
        copy.subtitleFiles = subtitleFiles?.map { file in
            var bookmarked = file
            bookmarked.bookmark = file.bookmark ?? FileBookmarks.make(for: file.url, securityScoped: securityScoped)
            return bookmarked
        }
        return copy
    }

    /// A completed job is never run again, so its bookmarks (about 3 KB of the ~4 KB a job
    /// takes in the saved queue) are dropped. Other jobs keep them: they can still be retried.
    public func droppingBookmarksWhenCompleted() -> EncodeJob {
        guard case .completed = state else { return self }
        var copy = self
        copy.sourceBookmark = nil
        copy.destinationFolderBookmark = nil
        copy.subtitleFiles = subtitleFiles?.map { file in
            var lean = file
            lean.bookmark = nil
            return lean
        }
        return copy
    }

    /// Follows bookmarks to where the files are now (refreshing stale ones). A job that
    /// is still waiting to run fails with a clear message if one of its files is gone.
    /// Jobs saved without bookmarks fall back to their stored paths and gain bookmarks.
    public func resolvingBookmarks(securityScoped: Bool = FileBookmarks.isSandboxed) -> EncodeJob {
        guard !state.isFinished else { return self }
        var copy = self
        var missing: [String] = []

        if let resolved = Self.locate(source, bookmark: sourceBookmark, securityScoped: securityScoped) {
            copy.source = resolved.url
            copy.sourceBookmark = resolved.bookmark
        } else {
            missing.append("source video “\(source.lastPathComponent)”")
        }

        let folder = destination.deletingLastPathComponent()
        if let resolved = Self.locateOutputFolder(folder, bookmark: destinationFolderBookmark, securityScoped: securityScoped) {
            copy.destination = resolved.url.appendingPathComponent(destination.lastPathComponent)
            copy.destinationFolderBookmark = resolved.bookmark
        } else {
            missing.append("destination folder “\(folder.lastPathComponent)”")
        }

        copy.subtitleFiles = subtitleFiles?.map { file in
            guard let resolved = Self.locate(file.url, bookmark: file.bookmark, securityScoped: securityScoped) else {
                missing.append("subtitle file “\(file.name)”")
                return file
            }
            var updated = file
            updated.url = resolved.url
            updated.bookmark = resolved.bookmark
            return updated
        }

        guard missing.isEmpty else {
            let list = ListFormatter.localizedString(byJoining: missing)
            return copy.with(state: .failed(message: "Can't find the \(list). It may have been moved, renamed or deleted."))
        }
        return copy
    }

    /// The output folder may not exist yet (it is created when the encode starts, and a
    /// bookmark can't point at it): the stored path stays valid while it can still be created.
    private static func locateOutputFolder(
        _ url: URL, bookmark: Data?, securityScoped: Bool
    ) -> (url: URL, bookmark: Data?)? {
        if let found = locate(url, bookmark: bookmark, securityScoped: securityScoped) { return found }
        return canCreateFolder(url) ? (url, nil) : nil
    }

    /// True when `url` is missing but its nearest existing ancestor is a folder.
    private static func canCreateFolder(_ url: URL) -> Bool {
        var current = url
        while current.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue && current != url
            }
            current = current.deletingLastPathComponent()
        }
        return false
    }

    private static func locate(
        _ url: URL, bookmark: Data?, securityScoped: Bool
    ) -> (url: URL, bookmark: Data?)? {
        if let bookmark, let resolved = FileBookmarks.resolve(bookmark, securityScoped: securityScoped) {
            return (resolved.url, resolved.refreshed ?? bookmark)
        }
        // No bookmark (older queue) or it no longer resolves: try the stored path.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, FileBookmarks.make(for: url, securityScoped: securityScoped))
    }
}
