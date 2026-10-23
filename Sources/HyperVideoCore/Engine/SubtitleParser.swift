import Foundation

public struct SubtitleCue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Reads SubRip (.srt) and WebVTT (.vtt) files into timed cues.
public enum SubtitleParser {
    public enum ParseError: LocalizedError {
        case noCues

        public var errorDescription: String? { "No subtitles were found in that file." }
    }

    public static func cues(from data: Data) throws -> [SubtitleCue] {
        let text = decode(data).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let cues = blocks(text).compactMap(cue)
        guard !cues.isEmpty else { throw ParseError.noCues }
        return cues.sorted { $0.start < $1.start }
    }

    /// Groups lines into cue blocks separated by blank or whitespace-only lines.
    static func blocks(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.split(whereSeparator: { $0.allSatisfy(\.isWhitespace) }).map { $0.joined(separator: "\n") }
    }

    /// UTF-8 (with or without BOM) or UTF-16 with BOM, else Windows-1252, which is
    /// what most older Latin-alphabet subtitles, Brazilian ones included, use.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        return String(data: body, encoding: .utf8)
            ?? String(data: body, encoding: .windowsCP1252)
            ?? String(decoding: body, as: UTF8.self)
    }

    private static func cue(_ block: String) -> SubtitleCue? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let parts = lines[timing].components(separatedBy: "-->")
        guard parts.count == 2,
              let start = seconds(parts[0]),
              let end = seconds(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""),
              end > start
        else { return nil }
        let text = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return SubtitleCue(start: start, end: end, text: stripMarkup(text))
    }

    /// `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or WebVTT's `MM:SS.mmm`.
    static func seconds(_ value: String) -> Double? {
        let fields = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        let numbers = fields.compactMap { Double($0) }
        guard numbers.count == fields.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    /// Drops HTML-style tags (`<i>`, `<font …>`) and ASS overrides (`{\an8}`).
    private static func stripMarkup(_ text: String) -> String {
        text.replacing(/<[^>]*>/, with: "").replacing(/\{\\[^}]*\}/, with: "")
    }

    /// Cues moved by `offset` milliseconds; starts clamp at 0 and cues ending at or before 0 are dropped.
    public static func shifted(_ cues: [SubtitleCue], byMs offset: Int) -> [SubtitleCue] {
        guard offset != 0 else { return cues }
        let delta = Double(offset) / 1000
        return cues.compactMap { cue in
            let end = cue.end + delta
            guard end > 0 else { return nil }
            return SubtitleCue(start: max(cue.start + delta, 0), end: end, text: cue.text)
        }
    }

    /// Cues cut to `start..<end`, with empty cues filling the gaps, so each cue is
    /// cleared on time in players that hold a sample until the next one.
    /// Overlapping cues are split at every boundary and their texts joined, one per line.
    public static func timeline(_ cues: [SubtitleCue], start: Double, end: Double) -> [SubtitleCue] {
        let clipped = cues.filter { min($0.end, end) - max($0.start, start) >= 0.01 }
        let edges = Set(clipped.flatMap { [max($0.start, start), min($0.end, end)] }).sorted()
        let spans = zip(edges, edges.dropFirst()).compactMap { from, to -> SubtitleCue? in
            guard to - from >= 0.01 else { return nil }
            let text = clipped.filter { $0.start <= from && $0.end >= to }.map(\.text).joined(separator: "\n")
            return text.isEmpty ? nil : SubtitleCue(start: from, end: to, text: text)
        }
        return spans.reduce(into: [SubtitleCue]()) { result, span in
            let cursor = result.last?.end ?? start
            if span.start - cursor >= 0.01 { result.append(SubtitleCue(start: cursor, end: span.start, text: "")) }
            result.append(SubtitleCue(start: cursor < span.start && span.start - cursor < 0.01 ? cursor : span.start,
                                      end: span.end, text: span.text))
        }
    }
}
