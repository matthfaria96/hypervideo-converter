import Foundation
import Testing
import HyperVideoCore
@testable import HyperVideoConverter

/// Chapter CSV import and export problems and decoding.
@Suite("Chapter files")
struct ChapterFileTests {
    @Test func exportProblemsAreNotCalledImports() {
        let failure = ChapterFileProblem.export("Disk full")
        #expect(failure.title == "Chapters not exported" && failure.message == "Disk full")
        #expect(ChapterFileProblem.import("Bad line").title == "Chapters not imported")
    }

    @Test func decodesUTF16WithByteOrderMark() throws {
        let text = "1,Ópening\n2,End"
        let little = try #require(text.data(using: .utf16LittleEndian))
        #expect(ChapterEditing.decodeCSV(Data([0xFF, 0xFE]) + little) == text)
        let big = try #require(text.data(using: .utf16BigEndian))
        #expect(ChapterEditing.decodeCSV(Data([0xFE, 0xFF]) + big) == text)
    }

    @Test func decodesUTF8AndWindowsLatin() {
        #expect(ChapterEditing.decodeCSV(Data([0xEF, 0xBB, 0xBF]) + Data("1,Intro".utf8)) == "1,Intro")
        #expect(ChapterEditing.decodeCSV(Data([0x31, 0x2C, 0x93, 0x41, 0x94])) == "1,\u{201C}A\u{201D}")
    }

    @Test func readingStopsPastTheLimitEvenWithoutAKnownSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x41, count: ChapterEditing.sizeLimit + 1).write(to: url)
        #expect(throws: ChapterCSV.ParseError.tooLarge) { try ChapterEditing.readCSV(at: url) }
        try Data("1,A".utf8).write(to: url)
        #expect(try ChapterEditing.readCSV(at: url) == Data("1,A".utf8))
    }
}
