import Foundation
import CoreMedia
import Testing
@testable import HyperVideoCore

@Suite("Subtitle files")
struct SubtitleFileTests {
    @Test func parsesSRTWithBOMCRLFTagsAndMultipleLines() throws {
        let srt = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Olá</i>, {\\an8}mundo\r\nsegunda linha\r\n\r\n2\r\n00:00:03,250 --> 00:00:04,000\r\nTchau\r\n"
        let cues = try SubtitleParser.cues(from: Data(srt.utf8))
        #expect(cues == [
            SubtitleCue(start: 1, end: 2.5, text: "Olá, mundo\nsegunda linha"),
            SubtitleCue(start: 3.25, end: 4, text: "Tchau")
        ])
    }

    @Test func fallsBackToWindows1252() throws {
        let latin = "1\n00:00:00,500 --> 00:00:01,000\nAção já\n".data(using: .windowsCP1252)!
        #expect(String(data: latin, encoding: .utf8) == nil, "fixture must not be valid UTF-8")
        #expect(try SubtitleParser.cues(from: latin).map(\.text) == ["Ação já"])
    }

    @Test func parsesWebVTT() throws {
        let vtt = "WEBVTT\n\nNOTE comment\n\ncue-1\n00:01.000 --> 00:02.000 align:start\nHello\n\n01:00:00.000 --> 01:00:01.500\nLater\n"
        let cues = try SubtitleParser.cues(from: Data(vtt.utf8))
        #expect(cues == [SubtitleCue(start: 1, end: 2, text: "Hello"), SubtitleCue(start: 3600, end: 3601.5, text: "Later")])
    }

    @Test func rejectsFilesWithoutCues() {
        #expect(throws: SubtitleParser.ParseError.self) { try SubtitleParser.cues(from: Data("just text".utf8)) }
    }

    @Test func languageComesFromTheFileName() {
        #expect(SubtitleFile.language(for: URL(fileURLWithPath: "/m/Movie.pt-BR.srt"), video: "Movie") == "pt-BR")
        #expect(SubtitleFile.language(for: URL(fileURLWithPath: "/m/Movie.en.vtt"), video: "Movie") == "en")
        #expect(SubtitleFile.language(for: URL(fileURLWithPath: "/m/Movie.srt"), video: "Movie") == nil)
        #expect(SubtitleFile.language(for: URL(fileURLWithPath: "/m/Movie.director cut.srt"), video: "Movie") == nil)
    }

    @Test func sidecarsAreFoundNextToTheVideo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HVCSubs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Trip.mov", "Trip.srt", "Trip.pt-BR.srt", "Trip.en.vtt", "Trip 2.srt", "Other.srt", "Trip.txt"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        let found = SubtitleFile.sidecars(for: dir.appendingPathComponent("Trip.mov"))
        #expect(found.map(\.url.lastPathComponent) == ["Trip.en.vtt", "Trip.pt-BR.srt", "Trip.srt"])
        #expect(found.map(\.language) == ["en", "pt-BR", nil])
    }

    @Test func timelineIsCutToTheTrimAndGapsAreFilled() {
        let cues = [SubtitleCue(start: 1, end: 2, text: "A"), SubtitleCue(start: 4, end: 6, text: "B"), SubtitleCue(start: 9, end: 10, text: "C")]
        let timeline = SubtitleParser.timeline(cues, start: 1.5, end: 5)
        #expect(timeline == [
            SubtitleCue(start: 1.5, end: 2, text: "A"),
            SubtitleCue(start: 2, end: 4, text: ""),
            SubtitleCue(start: 4, end: 5, text: "B")
        ])
    }

    @Test func whitespaceOnlySeparatorLinesSplitCues() throws {
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nA\n \t\n2\n00:00:03,000 --> 00:00:04,000\nB\n"
        #expect(try SubtitleParser.cues(from: Data(srt.utf8)) == [
            SubtitleCue(start: 1, end: 2, text: "A"), SubtitleCue(start: 3, end: 4, text: "B")
        ])
    }

    @Test func overlappingCuesAreMerged() {
        let cues = [SubtitleCue(start: 1, end: 5, text: "A"), SubtitleCue(start: 2, end: 3, text: "B"),
                    SubtitleCue(start: 4, end: 7, text: "C")]
        #expect(SubtitleParser.timeline(cues, start: 0, end: 10) == [
            SubtitleCue(start: 0, end: 1, text: ""),
            SubtitleCue(start: 1, end: 2, text: "A"),
            SubtitleCue(start: 2, end: 3, text: "A\nB"),
            SubtitleCue(start: 3, end: 4, text: "A"),
            SubtitleCue(start: 4, end: 5, text: "A\nC"),
            SubtitleCue(start: 5, end: 7, text: "C")
        ])
    }

    @Test func timedTextSamplesTileWithoutGaps() throws {
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        let a = try #require(TimedText.sample("a", start: 0.0009, duration: 0.0009, format: format))
        let b = try #require(TimedText.sample("b", start: 0.0018, duration: 1, format: format))
        let endA = CMSampleBufferGetPresentationTimeStamp(a) + CMSampleBufferGetDuration(a)
        #expect(endA == CMSampleBufferGetPresentationTimeStamp(b))
    }
}
