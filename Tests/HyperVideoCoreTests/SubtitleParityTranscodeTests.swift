@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Subtitle parity transcodes", .serialized)
struct SubtitleParityTranscodeTests {
    private func clip(_ languages: [String]) async throws -> (URL, URL, [Int]) {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 3,
                                                  subtitleLanguages: languages)
        let ids = try await MediaInspector.inspect(source).subtitleTracks.map(\.id)
        return (dir, source, ids)
    }

    private func convert(
        _ source: URL, container: ContainerFormat = .mov, files: [SubtitleFile] = [],
        configure: (inout EncodeSettings) -> Void
    ) async throws -> URL {
        var settings = EncodeSettings()
        settings.container = container
        configure(&settings)
        let out = source.deletingLastPathComponent().appendingPathComponent("out-\(UUID().uuidString).\(container.fileExtension)")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings, subtitleFiles: files) { _ in }
        return out
    }

    private func srt(in dir: URL, name: String = "extra.srt") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "1\n00:00:01,000 --> 00:00:02,000\nHello\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func languageListSelectsMatchingTrack() async throws {
        let (_, source, _) = try await clip(["en", "pt", "es"])
        let out = try await convert(source) { $0.subtitleOptions.languages = ["por"] }
        #expect(try await MediaInspector.inspect(out).subtitleTracks.map(\.language) == ["pt"])
    }

    @Test func explicitListSetsDefaultAndName() async throws {
        let (_, source, ids) = try await clip(["en", "pt", "es"])
        let out = try await convert(source) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: ids[0], include: false),
                SubtitleTrackSetting(sourceTrackID: ids[1]),
                SubtitleTrackSetting(sourceTrackID: ids[2], isDefault: true, name: "Español")
            ]
        }
        let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .subtitle)
        #expect(tracks.count == 2)
        #expect(try await tracks[0].load(.isEnabled) == false)
        #expect(try await tracks[1].load(.isEnabled) == true)
        #expect(await TrackNames.name(of: tracks[1]) == "Español")
    }

    @Test func forcedOnlyDropsNonForcedSource() async throws {
        let (_, source, ids) = try await clip(["en", "pt"])
        let out = try await convert(source) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: ids[0], forcedOnly: true),
                SubtitleTrackSetting(sourceTrackID: ids[1])
            ]
        }
        #expect(try await MediaInspector.inspect(out).subtitleTracks.map(\.language) == ["pt"])
    }

    @Test func externalFileOffsetShiftsCues() async throws {
        let (dir, source, _) = try await clip([])
        let file = SubtitleFile(url: try srt(in: dir), language: "en")
        let plain = try await convert(source, files: [file]) { _ in }
        var shifted = file
        shifted.offsetMs = 1000
        let later = try await convert(source, files: [shifted]) { _ in }
        let before = try await TranscodeIntegrationTests.textSamples(in: plain, trackIndex: 0).first { !$0.text.isEmpty }
        let after = try await TranscodeIntegrationTests.textSamples(in: later, trackIndex: 0).first { !$0.text.isEmpty }
        let delta = try #require(after?.start) - #require(before?.start)
        #expect(abs(delta - 1) < 0.02)
    }

    @Test func forcedFileWithTitleIsFlaggedAndNamed() async throws {
        let (dir, source, _) = try await clip([])
        let file = SubtitleFile(url: try srt(in: dir), language: "en", title: "Signs", isDefault: true, isForced: true)
        let out = try await convert(source, files: [file]) { _ in }
        let info = try await MediaInspector.inspect(out)
        #expect(info.subtitleTracks.first?.isForcedOnly == true)
        #expect(info.subtitleTracks.first?.name == "Signs")
    }

    @Test func matroskaCarriesNamesDefaultAndForcedFlags() async throws {
        let (dir, source, ids) = try await clip(["en", "pt"])
        let file = SubtitleFile(url: try srt(in: dir), language: "en", title: "Signs", isForced: true)
        let out = try await convert(source, container: .mkv, files: [file]) {
            $0.subtitleOptions.tracks = [
                SubtitleTrackSetting(sourceTrackID: ids[0], include: false),
                SubtitleTrackSetting(sourceTrackID: ids[1], isDefault: true, name: "Español")
            ]
        }
        let mkv = try MatroskaReader(url: out)
        let entries = try #require(mkv.segment?.child(EBML.ID.tracks)).all(EBML.ID.trackEntry)
        let subs = entries.filter { mkv.uint($0.child(EBML.ID.trackType)) == 0x11 }
        #expect(subs.count == 2)
        #expect(mkv.string(subs[0].child(EBML.ID.name)) == "Español")
        #expect(mkv.uint(subs[0].child(EBML.ID.flagDefault)) == 1)
        #expect(mkv.uint(subs[0].child(EBML.ID.flagForced)) == 0)
        #expect(mkv.string(subs[1].child(EBML.ID.name)) == "Signs")
        #expect(mkv.uint(subs[1].child(EBML.ID.flagForced)) == 1)
        #expect(mkv.uint(subs[1].child(EBML.ID.flagDefault)) == 0)
    }

    @Test func matroskaRemuxerWritesAudioName() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 1)
        let named = try await copyingAudio(from: source, name: "Director", to: dir.appendingPathComponent("named.mov"))
        let out = dir.appendingPathComponent("named.mkv")
        try await MatroskaRemuxer(source: named, destination: out).run(cancel: CancelFlag()) { _ in }
        let mkv = try MatroskaReader(url: out)
        let entries = try #require(mkv.segment?.child(EBML.ID.tracks)).all(EBML.ID.trackEntry)
        let audio = try #require(entries.first { mkv.uint($0.child(EBML.ID.trackType)) == 2 })
        #expect(mkv.string(audio.child(EBML.ID.name)) == "Director")
        #expect(mkv.uint(audio.child(EBML.ID.flagDefault)) == 1)
    }

    /// Copies video and audio samples unchanged into a MOV whose audio track carries `name`.
    private func copyingAudio(from source: URL, name: String, to destination: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for type in [AVMediaType.video, .audio] {
            let track = try #require(try await asset.loadTracks(withMediaType: type).first)
            let hint = try await track.load(.formatDescriptions).first
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            if type == .audio { input.metadata = TrackNames.items(name) }
            reader.add(output)
            writer.add(input)
            pairs.append((output, input))
        }
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var samples: [[CMSampleBuffer]] = []
        for (output, _) in pairs {
            var list: [CMSampleBuffer] = []
            while let sample = output.copyNextSampleBuffer() { list.append(sample) }
            samples.append(list)
        }
        var cursors = Array(repeating: 0, count: pairs.count)
        while cursors.indices.contains(where: { cursors[$0] < samples[$0].count }) {
            for (index, pair) in pairs.enumerated() where cursors[index] < samples[index].count {
                guard pair.1.isReadyForMoreMediaData else { continue }
                pair.1.append(samples[index][cursors[index]])
                cursors[index] += 1
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        pairs.forEach { $0.1.markAsFinished() }
        await writer.finishWriting()
        return destination
    }
}
