@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Chapter and tag transcodes", .serialized)
struct ChapterTagTranscodeTests {
    private static let tags = MetadataTags(
        title: "My Title", actors: "An Actor", director: "A Director", releaseDate: "2024-05-06",
        comment: "A comment", genre: "Drama", description: "Short text", plot: "Long plot text")

    private func run(_ source: URL, _ settings: EncodeSettings, ext: String) async throws -> URL {
        var settings = settings
        settings.videoCodec = .h264
        let out = source.deletingLastPathComponent().appendingPathComponent("out-\(UUID().uuidString).\(ext)")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        return out
    }

    private func clip(chapters: [String] = ["A", "B", "C"]) async throws -> URL {
        let dir = try TranscodeIntegrationTests.tempDir()
        return try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 3, chapters: chapters)
    }

    @Test func editedTitlesReachMP4AndMKV() async throws {
        let source = try await clip()
        var settings = EncodeSettings()
        settings.chapterOptions.titles = ["", "Middle", ""]
        let mp4 = try await run(source, settings, ext: "mp4")
        #expect(try await MediaInspector.inspect(mp4).chapters.map(\.title) == ["A", "Middle", "C"])
        settings.container = .mkv
        let mkv = try MatroskaReader(url: try await run(source, settings, ext: "mkv"))
        #expect(mkv.chapters.map(\.0) == ["A", "Middle", "C"])
    }

    @Test func markersSwitchIsIndependentOfKeepMetadata() async throws {
        let source = try await clip()
        var settings = EncodeSettings()
        settings.keepMetadata = false
        let none = try await run(source, settings, ext: "mp4")
        #expect(try await MediaInspector.inspect(none).chapters.isEmpty)
        settings.chapterOptions.markers = true
        let some = try await run(source, settings, ext: "mp4")
        #expect(try await MediaInspector.inspect(some).chapters.count == 3)
        settings.keepMetadata = true
        settings.chapterOptions.markers = false
        let off = try await run(source, settings, ext: "mp4")
        #expect(try await MediaInspector.inspect(off).chapters.isEmpty)
    }

    private func stringValues(_ url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        var values: [String] = []
        for item in try await asset.load(.metadata) { if let text = try await item.load(.stringValue) { values.append(text) } }
        return values
    }

    @Test(arguments: [(ContainerFormat.mp4, "mp4"), (.mov, "mov")])
    func tagsReadBackInMovieContainers(container: ContainerFormat, ext: String) async throws {
        let source = try await clip(chapters: [])
        var settings = EncodeSettings()
        settings.container = container
        settings.tags = Self.tags
        let out = try await run(source, settings, ext: ext)
        let values = try await stringValues(out)
        for expected in ["My Title", "An Actor", "A Director", "A comment", "Drama", "Short text", "Long plot text"] {
            #expect(values.contains(expected), "\(expected) missing from \(values)")
        }
        #expect(values.contains { $0.hasPrefix("2024-05-06") }, "\(values)")
        let common = try await AVURLAsset(url: out).load(.commonMetadata)
        let title = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierTitle)
        #expect(try await title.first?.load(.stringValue) == "My Title")
    }

    @Test func tagsReadBackInMKV() async throws {
        let source = try await clip(chapters: [])
        var settings = EncodeSettings()
        settings.container = .mkv
        settings.tags = Self.tags
        let mkv = try MatroskaReader(url: try await run(source, settings, ext: "mkv"))
        let values = mkv.tagValues
        #expect(values["TITLE"] == "My Title")
        #expect(values["ACTOR"] == "An Actor" || values["ARTIST"] == "An Actor")
        #expect(values["DIRECTOR"] == "A Director")
        #expect(values["DATE_RELEASED"]?.hasPrefix("2024-05-06") == true, "\(values)")
        #expect(values["COMMENT"] == "A comment")
        #expect(values["GENRE"] == "Drama")
        #expect(values["DESCRIPTION"] == "Short text")
        #expect(values["SYNOPSIS"] == "Long plot text")
        #expect(mkv.title == "My Title")
    }

    private func sourceWithTitle(_ title: String) async throws -> URL {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataTitle
        item.value = title as NSString
        var spec = StressClip.Spec()
        spec.metadata = [item]
        return try await StressClip.make(in: try TranscodeIntegrationTests.tempDir(), spec)
    }

    @Test func userTitleReplacesSourceTitleWithoutPassthrough() async throws {
        let source = try await sourceWithTitle("Source Title")
        var settings = EncodeSettings()
        settings.keepMetadata = false
        settings.container = .mov
        settings.tags = MetadataTags(title: "Mine")
        let values = try await stringValues(try await run(source, settings, ext: "mov"))
        #expect(values == ["Mine"])
    }

    @Test func defaultSettingsKeepSourceMetadata() async throws {
        let source = try await sourceWithTitle("Source Title")
        let sourceCount = try await AVURLAsset(url: source).load(.metadata).count
        var settings = EncodeSettings()
        settings.container = .mov
        let out = try await run(source, settings, ext: "mov")
        #expect(try await AVURLAsset(url: out).load(.metadata).count == sourceCount)
        #expect(try await stringValues(out).contains("Source Title"))
    }
}
