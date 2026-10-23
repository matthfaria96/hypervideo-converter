@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Chapter and tag parity")
struct ChapterTagParityTests {
    @Test func csvFormatsAndParsesQuotedTitles() throws {
        let text = ChapterCSV.format(["Intro", "Say \"hi\", Bob"])
        #expect(text == "1,\"Intro\"\n2,\"Say \"\"hi\"\", Bob\"\n")
        #expect(try ChapterCSV.parse(text) == [1: "Intro", 2: "Say \"hi\", Bob"])
    }

    @Test func csvFormatFoldsLineBreaks() throws {
        let text = ChapterCSV.format(["Part\none", "Two\r\nlines", "Three\rx"])
        #expect(try ChapterCSV.parse(text) == [1: "Part one", 2: "Two lines", 3: "Three x"])
    }

    @Test func longCueIsCutOnACharacterBoundary() throws {
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Text))
        let text = String(repeating: "a", count: Int(UInt16.max) - 1) + "é"
        let sample = try #require(TimedText.sample(text, start: 0, duration: 1, format: format))
        let block = try #require(CMSampleBufferGetDataBuffer(sample))
        var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: &bytes)
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        #expect(length == Int(UInt16.max) - 1)
        #expect(String(validating: bytes[2...].prefix(length), as: UTF8.self) != nil)
    }

    @Test func csvAcceptsLooseInput() throws {
        let text = "\u{FEFF}3,Plain title\r\n\r\n4,A\\, B\r\n"
        #expect(try ChapterCSV.parse(text) == [3: "Plain title", 4: "A, B"])
    }

    @Test func csvRejectsBadLinesAndHugeInput() {
        #expect(throws: ChapterCSV.ParseError.invalidLine(2)) { try ChapterCSV.parse("1,ok\nnope\n") }
        #expect(throws: ChapterCSV.ParseError.tooLarge) { try ChapterCSV.parse(String(repeating: "a", count: 1_048_577)) }
        #expect(ChapterCSV.ParseError.invalidLine(2).errorDescription == "Line 2 of the chapter file isn't “number,title”.")
        #expect(ChapterCSV.ParseError.tooLarge.errorDescription == "The chapter file is too large.")
    }

    @Test func csvTitlesApplyAndPad() {
        #expect(ChapterCSV.titles(applying: [2: "Two", 9: "Nine"], to: ["", ""], count: 3) == ["", "Two", ""])
    }

    private let chapters = [Chapter(title: "A", start: 0, duration: 10), Chapter(title: "B", start: 10, duration: 10),
                            Chapter(title: "C", start: 20, duration: 10)]

    @Test func renamedKeepsSourceForBlankTitles() {
        #expect(Chapter.renamed(chapters, titles: ["", "Middle"]).map(\.title) == ["A", "Middle", "C"])
        #expect(Chapter.renamed(chapters, titles: ["  ", "x"]).map(\.title) == ["A", "x", "C"])
    }

    @Test func chapterRangeBecomesTrim() {
        #expect(TrimRange.chapters(chapters, from: 1, through: 2) == TrimRange(start: 10, end: 30))
        #expect(TrimRange.chapters(chapters, from: 0, through: 0) == TrimRange(start: 0, end: 10))
        #expect(TrimRange.chapters(chapters, from: 2, through: 1) == nil)
        #expect(TrimRange.chapters(chapters, from: 1, through: 5) == nil)
    }

    @Test func tagItemsFollowTheIdentifierTable() {
        let tags = MetadataTags(title: "T", director: "D", plot: "P")
        let mp4 = WriterMetadata.tagItems(tags, container: .mp4)
        #expect(mp4.compactMap(\.identifier) == [
            .iTunesMetadataSongName, .iTunesMetadataDirector,
            AVMetadataItem.identifier(forKey: "ldes" as NSString, keySpace: .iTunes) ?? .iTunesMetadataSongName
        ])
        #expect(mp4.compactMap { $0.value as? String } == ["T", "D", "P"])
        let mov = WriterMetadata.tagItems(tags, container: .mkv)
        #expect(mov.compactMap(\.identifier) == [.quickTimeMetadataTitle, .quickTimeMetadataDirector, .quickTimeMetadataInformation])
        #expect(WriterMetadata.tagItems(MetadataTags(title: "  ", comment: ""), container: .mov).isEmpty)
    }

    @Test func mergeDropsOverriddenSourceItems() {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = id
            item.value = value as NSString
            return item
        }
        let base = [item(.commonIdentifierTitle, "Source"), item(.quickTimeMetadataComment, "keep")]
        let merged = WriterMetadata.merged(base: base, tags: MetadataTags(title: "T"), container: .mov)
        #expect(merged.compactMap { $0.value as? String }.sorted() == ["T", "keep"])
        #expect(WriterMetadata.merged(base: base, tags: MetadataTags(), container: .mov).count == 2)
    }
}
