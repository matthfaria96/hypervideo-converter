import Foundation

/// An external subtitle file (SRT or WebVTT) added to one source video.
public struct SubtitleFile: Codable, Hashable, Identifiable, Sendable {
    public var url: URL
    public var language: String?

    public init(url: URL, language: String?) {
        self.url = url
        self.language = language
    }

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public static let fileExtensions: Set<String> = ["srt", "vtt"]

    /// Subtitle files beside `video` named after it, e.g. `Movie.srt` or `Movie.pt-BR.srt`.
    public static func sidecars(for video: URL) -> [SubtitleFile] {
        let base = video.deletingPathExtension().lastPathComponent
        let folder = video.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
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
