@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

/// "Forced only" on a track that mixes forced and normal cues keeps just the forced ones.
@Suite("Forced subtitle transcodes", .serialized)
struct ForcedSubtitleTranscodeTests {
    /// A tx3g cue whose sample carries a `frcd` box when `forced`.
    static func cue(_ text: String, at seconds: Double, forced: Bool, format: CMFormatDescription) throws -> CMSampleBuffer {
        let utf8 = Array(text.utf8)
        let box: [UInt8] = forced ? [0, 0, 0, 8] + Array("frcd".utf8) : []
        let bytes = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8 + box
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes.count,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        let data = try #require(block)
        _ = bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map {
                CMBlockBufferReplaceDataBytes(with: $0, blockBuffer: data, offsetIntoDestination: 0, dataLength: bytes.count)
            }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 600, timescale: 600),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
                                        decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: data, formatDescription: format, sampleCount: 1,
                                  sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                  sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        return try #require(sample)
    }

    /// Adds a subtitle track (one 1 s cue per second, the second forced) to a short video clip.
    static func mixedClip(in dir: URL) async throws -> URL {
        let video = try await ParityClip.make(in: dir, .init(name: "mixed-video", frameTimes: (0..<90).map { Double($0) / 30 }))
        let url = dir.appendingPathComponent("mixed.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let asset = AVURLAsset(url: video)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                            sourceFormatHint: try await track.load(.formatDescriptions).first)
        let format = try #require(TimedText.format(mediaType: kCMMediaType_Subtitle))
        let textInput = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
        textInput.extendedLanguageTag = "en"
        [videoInput, textInput].forEach { $0.expectsMediaDataInRealTime = false; writer.add($0) }
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let cues = try ["One", "Forced", "Three"].enumerated().map {
            try cue($0.element, at: Double($0.offset), forced: $0.offset == 1, format: format)
        }
        for sample in cues {
            while !textInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            textInput.append(sample)
        }
        textInput.markAsFinished()
        while let sample = output.copyNextSampleBuffer() {
            while !videoInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            videoInput.append(sample)
        }
        videoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TranscodeError.noTracks }
        return url
    }

    @Test func forcedOnlyKeepsJustTheForcedCues() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await Self.mixedClip(in: dir)
        let id = try #require(try await MediaInspector.inspect(source).subtitleTracks.first?.id)
        var settings = EncodeSettings()
        settings.container = .mov
        settings.subtitleOptions.tracks = [SubtitleTrackSetting(sourceTrackID: id, forcedOnly: true)]
        let out = dir.appendingPathComponent("forced-out.mov")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        try #require(try await AVURLAsset(url: out).loadTracks(withMediaType: .subtitle).count == 1)
        let texts = try await TranscodeIntegrationTests.textSamples(in: out, trackIndex: 0).map(\.text).filter { !$0.isEmpty }
        #expect(texts == ["Forced"])
        #expect(try await MediaInspector.inspect(out).subtitleTracks.first?.forcedOnly == true)
    }
}
