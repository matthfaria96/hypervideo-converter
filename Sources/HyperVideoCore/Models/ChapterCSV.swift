import Foundation

/// HandBrake's chapter-name CSV: one `number,title` line per chapter.
public enum ChapterCSV {
    public enum ParseError: LocalizedError, Equatable {
        case invalidLine(Int)
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidLine(let line): "Line \(line) of the chapter file isn't “number,title”."
            case .tooLarge: "The chapter file is too large."
            }
        }
    }

    static let sizeLimit = 1_048_576

    /// Chapter number (1-based) to title.
    public static func parse(_ text: String) throws -> [Int: String] {
        guard text.utf8.count <= sizeLimit else { throw ParseError.tooLarge }
        var cleaned = text.replacingOccurrences(of: "\r", with: "")
        if cleaned.hasPrefix("\u{FEFF}") { cleaned.removeFirst() }
        var result: [Int: String] = [:]
        for (index, line) in cleaned.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let comma = line.firstIndex(of: ","),
                  let number = Int(line[..<comma].trimmingCharacters(in: .whitespaces)) else {
                throw ParseError.invalidLine(index + 1)
            }
            result[number] = unquote(String(line[line.index(after: comma)...]))
        }
        return result
    }

    /// One line per title; line breaks inside a title become spaces so `parse` reads it back.
    public static func format(_ titles: [String]) -> String {
        titles.enumerated().map { index, title in
            let line = title.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
            return "\(index + 1),\"\(line.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
        }.joined()
    }

    /// `existing` with the parsed titles written in, padded with empty strings to `count`.
    public static func titles(applying parsed: [Int: String], to existing: [String], count: Int) -> [String] {
        var result = Array(existing.prefix(count))
        result += Array(repeating: "", count: max(0, count - result.count))
        for (number, title) in parsed where number >= 1 && number <= count { result[number - 1] = title }
        return result
    }

    private static func unquote(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }
        return value.replacingOccurrences(of: "\\,", with: ",")
    }
}
