import Foundation
import HyperVideoCore

/// Pure and off-main helpers behind the Chapters, Tags and chapter-range controls.
enum ChapterEditing {
    private static let boundaryTolerance = 0.05
    /// The core's `ChapterCSV` limit (1 MiB); kept in step until the core exposes its own.
    static let sizeLimit = 1_048_576

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
            let parsed = try ChapterCSV.parse(decodeCSV(try readCSV(at: url)))
            return ChapterCSV.titles(applying: parsed, to: existing, count: chapterCount)
        }.value
    }

    /// Reads at most one byte past the limit, so a huge file (or one whose size the
    /// file system doesn't report) is never loaded whole.
    static func readCSV(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: sizeLimit + 1) ?? Data()
        guard data.count <= sizeLimit else { throw ChapterCSV.ParseError.tooLarge }
        return data
    }

    /// UTF-16 when the file starts with a byte order mark (Excel's "Unicode Text"),
    /// else UTF-8, else Windows Latin-1, which accepts any bytes.
    static func decodeCSV(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        return String(data: body, encoding: .utf8)
            ?? String(data: body, encoding: .windowsCP1252)
            ?? String(decoding: body, as: UTF8.self)
    }

    static func exportCSV(titles: [String], to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try ChapterCSV.format(titles).write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}

/// A chapter file that couldn't be read or written, with the alert title to match.
enum ChapterFileProblem: Equatable {
    case `import`(String)
    case export(String)

    var title: String {
        switch self {
        case .import: String(localized: "Chapters not imported")
        case .export: String(localized: "Chapters not exported")
        }
    }

    var message: String {
        switch self {
        case .import(let text), .export(let text): text
        }
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
