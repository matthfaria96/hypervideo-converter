@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

/// Align A/V Start on sources whose video lead-in is a sample offset rather than an empty edit.
@Suite("A/V alignment", .serialized)
struct AVAlignmentTests {
    /// A movie whose video samples all present `offset` seconds after they decode (as with an
    /// uncompensated B-frame or remuxed-stream start offset), with one edit from media time 0
    /// and no empty edit. Audio starts at 0.
    static func offsetVideoMovie(in dir: URL, offset: Double) async throws -> URL {
        let plain = try await StressClip.make(in: dir, StressClip.Spec(name: "plain", seconds: 1.5))
        let asset = AVURLAsset(url: plain)
        let url = dir.appendingPathComponent("offset.mov")
        let movie = AVMutableMovie()
        movie.defaultMediaDataStorage = AVMediaDataStorage(url: url)
        let audioSource = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let audio = try #require(movie.addMutableTrack(withMediaType: .audio, copySettingsFrom: nil))
        try audio.insertTimeRange(try await audioSource.load(.timeRange), of: audioSource, at: .zero, copySampleData: true)

        let videoSource = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let video = try #require(movie.addMutableTrack(withMediaType: .video, copySettingsFrom: nil))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoSource, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        let shift = CMTime(seconds: offset, preferredTimescale: 6_000)
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let dts = CMSampleBufferGetDecodeTimeStamp(sample)
            var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample),
                                            presentationTimeStamp: pts + shift,
                                            decodeTimeStamp: dts.isValid ? dts : pts)
            var shifted: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing, sampleBufferOut: &shifted)
            try video.append(try #require(shifted), decodeTime: nil, presentationTime: nil)
        }
        let media = video.mediaDecodeTimeRange
        let span = CMTimeRange(start: .zero, duration: media.duration + shift)
        #expect(video.insertMediaTimeRange(span, into: span))
        try movie.writeHeader(to: url, fileType: .mov, options: .addMovieHeaderToDestination)
        return url
    }

    @Test func sampleOffsetLeadInIsAligned() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let url = try await Self.offsetVideoMovie(in: dir, offset: 0.5)
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let segments = try await track.load(.segments)
        #expect(segments.allSatisfy { !$0.isEmpty }, "fixture must have no empty edit")
        var settings = EncodeSettings()
        settings.alignAVStart = true
        let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let start = await AVAlignment.sessionStart(asset: asset, range: range, settings: settings)
        #expect(abs(start.seconds - 0.5) < 0.02, "\(start.seconds)")
    }

    @Test func alignedEncodeOfSampleOffsetSourceDropsTheLeadIn() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await Self.offsetVideoMovie(in: dir, offset: 0.5)
        var settings = EncodeSettings()
        settings.container = .mov
        let plain = dir.appendingPathComponent("plain-out.mov")
        _ = try await TranscodeEngine().run(source: source, destination: plain, settings: settings) { _ in }
        settings.alignAVStart = true
        let aligned = dir.appendingPathComponent("aligned.mov")
        _ = try await TranscodeEngine().run(source: source, destination: aligned, settings: settings) { _ in }
        let off = try await MediaInspector.inspect(plain).duration
        let on = try await MediaInspector.inspect(aligned).duration
        // The 0.5 s of audio before the first picture is cut.
        #expect(abs((off - on) - 0.5) < 0.1, "off \(off) on \(on)")
    }
}
