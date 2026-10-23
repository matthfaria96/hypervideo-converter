import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

@Suite("Summary, chapters and tags")
struct SummaryChaptersTagsTests {
    private let chapters = [
        Chapter(title: "A", start: 0, duration: 10),
        Chapter(title: "B", start: 10, duration: 10),
        Chapter(title: "C", start: 20, duration: 10)
    ]

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    @Test func titleFallsBackToSource() {
        #expect(ChapterEditing.title(at: 1, chapters: chapters, titles: ["", "Mid"]) == "Mid")
        #expect(ChapterEditing.title(at: 2, chapters: chapters, titles: ["", "Mid"]) == "C")
        #expect(ChapterEditing.title(at: 0, chapters: chapters, titles: ["", "Mid"]) == "A")
    }

    @Test func settingTitleStoresOverrideOrBlank() {
        let set = ChapterEditing.settingTitle("Mid", at: 1, chapters: chapters, options: ChapterOptions())
        #expect(set.titles == ["", "Mid", ""])
        let back = ChapterEditing.settingTitle("B", at: 1, chapters: chapters, options: set)
        #expect(back.titles == ["", "", ""])
    }

    @Test func rangeIndicesMatchBoundaries() {
        let range = ChapterEditing.rangeIndices(trim: TrimRange(start: 10, end: 30), chapters: chapters)
        #expect(range?.from == 1)
        #expect(range?.through == 2)
        #expect(ChapterEditing.rangeIndices(trim: nil, chapters: chapters)?.through == 2)
        #expect(ChapterEditing.rangeIndices(trim: TrimRange(start: 11, end: 30), chapters: chapters) == nil)
    }

    @Test func importTitlesReadsCSV() async throws {
        let url = tempURL("c.csv")
        try "1,\"One\"\n3,\"Three\"".write(to: url, atomically: true, encoding: .utf8)
        let titles = try await ChapterEditing.importTitles(from: url, chapterCount: 3, existing: [])
        #expect(titles == ["One", "", "Three"])
    }

    @Test func importRejectsInvalidAndLargeFiles() async throws {
        let bad = tempURL("bad.csv")
        try "nonsense".write(to: bad, atomically: true, encoding: .utf8)
        await #expect(throws: ChapterCSV.ParseError.invalidLine(1)) {
            _ = try await ChapterEditing.importTitles(from: bad, chapterCount: 3, existing: [])
        }
        let big = tempURL("big.csv")
        try Data(repeating: 0x41, count: 1_048_577).write(to: big)
        await #expect(throws: ChapterCSV.ParseError.tooLarge) {
            _ = try await ChapterEditing.importTitles(from: big, chapterCount: 3, existing: [])
        }
    }

    @Test func exportWritesFormattedCSV() async throws {
        let url = tempURL("out.csv")
        try await ChapterEditing.exportCSV(titles: ["A", "B"], to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == ChapterCSV.format(["A", "B"]))
    }

    @Test func tagSettingTrimsBlankToNil() {
        #expect(MetadataTags().setting(\.title, "  ").title == nil)
        #expect(MetadataTags().setting(\.genre, "Drama").genre == "Drama")
    }
}
