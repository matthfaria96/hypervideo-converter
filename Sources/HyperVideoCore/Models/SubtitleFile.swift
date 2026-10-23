import Foundation

/// An external subtitle file (SRT or WebVTT) added to one source video.
public struct SubtitleFile: Codable, Hashable, Identifiable, Sendable {
    public var url: URL
    public var language: String?
    /// Finds the file after relaunches or moves; nil in queues saved before it existed.
    public var bookmark: Data?
    /// Shifts every cue by this many milliseconds.
    public var offsetMs: Int = 0
    /// Track title written to the output.
    public var title: String?
    public var isDefault = false
    public var isForced = false

    public init(
        url: URL, language: String?, bookmark: Data? = nil,
        offsetMs: Int = 0, title: String? = nil, isDefault: Bool = false, isForced: Bool = false
    ) {
        self.url = url
        self.language = language
        self.bookmark = bookmark
        self.offsetMs = offsetMs
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
    }

    private enum CodingKeys: String, CodingKey {
        case url, language, bookmark, offsetMs, title, isDefault, isForced
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        offsetMs = try c.decodeIfPresent(Int.self, forKey: .offsetMs) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isForced = try c.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
    }

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public static let fileExtensions: Set<String> = ["srt", "vtt"]

    /// Subtitle files beside `video` named after it, e.g. `Movie.srt` or `Movie.pt-BR.srt`.
    public static func sidecars(for video: URL) -> [SubtitleFile] {
        let folder = video.deletingLastPathComponent()
        return sidecars(for: video, among: (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// The same for many videos, listing each folder once instead of once per video.
    public static func sidecars(for videos: [URL]) -> [URL: [SubtitleFile]] {
        var listings: [String: [String]] = [:]
        var result: [URL: [SubtitleFile]] = [:]
        for video in videos {
            let folder = video.deletingLastPathComponent().path
            if listings[folder] == nil {
                listings[folder] = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            }
            let found = sidecars(for: video, among: listings[folder] ?? [])
            if !found.isEmpty { result[video] = found }
        }
        return result
    }

    private static func sidecars(for video: URL, among names: [String]) -> [SubtitleFile] {
        let base = video.deletingPathExtension().lastPathComponent
        let folder = video.deletingLastPathComponent()
        return names
            .filter { name in
                let url = URL(fileURLWithPath: name)
                return fileExtensions.contains(url.pathExtension.lowercased())
                    && (url.deletingPathExtension().lastPathComponent == base || name.hasPrefix(base + "."))
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { name in
                let url = folder.appendingPathComponent(name)
                return SubtitleFile(url: url, language: language(for: url, video: base))
            }
    }

    /// The language tag between the video's name and the extension, when it looks like
    /// one (`en`, `pt-BR`, `zh-Hant`); nil for plain `Movie.srt` or free-form labels.
    public static func language(for file: URL, video base: String) -> String? {
        let stem = file.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix(base + ".") else { return nil }
        let tag = String(stem.dropFirst(base.count + 1))
        let pattern = /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/
        return tag.wholeMatch(of: pattern) == nil ? nil : tag
    }
}
