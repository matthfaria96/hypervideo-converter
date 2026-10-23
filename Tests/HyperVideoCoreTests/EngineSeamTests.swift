@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Engine seams")
struct EngineSeamTests {
    private func samples(_ count: Int) throws -> [CMSampleBuffer] {
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        return try (0..<count).map { index in
            try #require(TimedText.sample("cue \(index)", start: Double(index), duration: 1, format: format))
        }
    }

    @Test func transformDropsAndReplacesSamples() throws {
        let all = try samples(4)
        var iterator = all.makeIterator()
        var seen = 0
        let next = SamplePump.filtered({ iterator.next() }, { buffer in
            defer { seen += 1 }
            return seen == 1 ? nil : buffer
        })
        var out: [CMSampleBuffer] = []
        while let buffer = try next() { out.append(buffer) }
        #expect(out.count == 3)
        #expect(out[0] === all[0])
        #expect(out[1] === all[2])
        #expect(out[2] === all[3])
    }

    @Test func nilTransformPassesEverything() throws {
        let all = try samples(4)
        var iterator = all.makeIterator()
        let next = SamplePump.filtered({ iterator.next() }, nil)
        var count = 0
        while try next() != nil { count += 1 }
        #expect(count == 4)
    }

    /// Copies the audio track of a StressClip into a new file whose track carries a name.
    private func namedAudio(type: AVFileType, name: String, in dir: URL) async throws -> String? {
        let source = try await StressClip.make(in: dir, .init(name: "named-source"))
        let asset = AVURLAsset(url: source)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let url = dir.appendingPathComponent("named.\(type == .mp4 ? "mp4" : "mov")")
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        input.metadata = TrackNames.items(name)
        writer.add(input)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        while let sample = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            input.append(sample)
        }
        input.markAsFinished()
        await writer.finishWriting()
        let written = AVURLAsset(url: url)
        guard let audio = try await written.loadTracks(withMediaType: .audio).first else { return nil }
        return await TrackNames.name(of: audio)
    }

    @Test func trackNameRoundTripsInMOV() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try await namedAudio(type: .mov, name: "Commentary", in: dir) == "Commentary")
    }

    @Test func trackNameProbeInMP4() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try await namedAudio(type: .mp4, name: "Commentary", in: dir)
        Issue.record("MP4 track name probe: \(name ?? "dropped")", severity: .warning)
    }

    @Test func writerMetadataFollowsKeepMetadata() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = "Seam" as NSString
        title.extendedLanguageTag = "und"
        let url = try await StressClip.make(in: dir, .init(name: "meta", metadata: [title]))
        let asset = AVURLAsset(url: url)
        let expected = try await asset.load(.metadata).count
        #expect(expected > 0)
        var settings = EncodeSettings()
        settings.keepMetadata = false
        #expect(await WriterMetadata.items(source: asset, settings: settings).isEmpty)
        settings.keepMetadata = true
        #expect(await WriterMetadata.items(source: asset, settings: settings).count == expected)
    }
}
