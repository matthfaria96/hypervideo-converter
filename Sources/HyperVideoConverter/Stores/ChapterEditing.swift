import Foundation
import HyperVideoCore

/// Pure and off-main helpers behind the Chapters, Tags and chapter-range controls.
enum ChapterEditing {
    private static let boundaryTolerance = 0.05
    private static let sizeLimit = 1_048_576

    /// The edited title for chapter `index`, or the source title when none is set.
    static func title(at index: Int, chapters: [Chapter], titles: [String]) -> String {
        if index < titles.count, !titles[index].isEmpty { return titles[index] }
        return chapters.indices.contains(index) ? chapters[index].title : ""
    }

    static func effectiveTitles(chapters: [Chapter], titles: [String]) -> [String] {
        chapters.indices.map { title(at: $0, chapters: chapters, titles: titles) }
    }

    /// Stores `text` as the override for chapter `index`; the source title is stored as blank.
    static func settingTitle(_ text: String, at index: Int, chapters: [Chapter], options: ChapterOptions) -> ChapterOptions {
        guard chapters.indices.contains(index) else { return options }
        var result = options
        var titles = Array(options.titles.prefix(chapters.count))
        titles += Array(repeating: "", count: chapters.count - titles.count)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[index] = trimmed == chapters[index].title ? "" : trimmed
        result.titles = titles
        return result
    }

    /// The chapter range a trim covers, or nil when it doesn't sit on chapter boundaries.
    static func rangeIndices(trim: TrimRange?, chapters: [Chapter]) -> (from: Int, through: Int)? {
        guard let last = chapters.indices.last else { return nil }
        guard let trim else { return (0, last) }
        let end = trim.end ?? chapters[last].end
        guard let from = chapters.firstIndex(where: { abs($0.start - trim.start) <= boundaryTolerance }),
              let through = chapters.firstIndex(where: { abs($0.end - end) <= boundaryTolerance }),
              from <= through else { return nil }
        return (from, through)
    }

    static func importTitles(from url: URL, chapterCount: Int, existing: [String]) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= sizeLimit else { throw ChapterCSV.ParseError.tooLarge }
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let parsed = try ChapterCSV.parse(text)
            return ChapterCSV.titles(applying: parsed, to: existing, count: chapterCount)
        }.value
    }

    static func exportCSV(titles: [String], to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try ChapterCSV.format(titles).write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}

extension MetadataTags {
    /// A copy with the field set to `text`; blank text clears it.
    func setting(_ keyPath: WritableKeyPath<MetadataTags, String?>, _ text: String) -> MetadataTags {
        var copy = self
        copy[keyPath: keyPath] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        return copy
    }
}
