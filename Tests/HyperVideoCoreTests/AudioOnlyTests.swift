import AVFoundation
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Audio only (M4A)", .serialized)
struct AudioOnlyTests {
    @Test func extractsTheAudioWithoutThePicture() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-m4a-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 160, height: 90), seconds: 2)
        var settings = EncodeSettings()
        settings.container = .m4a
        let progress = ProgressLog()
        let output = try await TranscodeEngine().transcode(source: source, destination: dir.appendingPathComponent("out.m4a"),
                                                           settings: settings) { progress.add($0) }
        #expect(output.url.pathExtension == "m4a")
        let asset = AVURLAsset(url: output.url)
        #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.2)
        #expect(progress.last == 1)
    }

    @Test func trimIsRespected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-m4a-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 160, height: 90), seconds: 3)
        var settings = EncodeSettings()
        settings.container = .m4a
        settings.trim = TrimRange(start: 1, end: 2)
        let output = try await TranscodeEngine().transcode(source: source, destination: dir.appendingPathComponent("t.m4a"),
                                                           settings: settings) { _ in }
        #expect(abs(try await AVURLAsset(url: output.url).load(.duration).seconds - 1) < 0.2)
    }

    @Test func needsAudioToKeep() {
        var settings = EncodeSettings()
        settings.container = .m4a
        settings.audioCodec = .none
        #expect(!settings.isValid)
    }

    @Test func predictsOnlyTheAudio() throws {
        let info = MediaInfo(url: URL(fileURLWithPath: "/tmp/a.mov"), duration: 100, displaySize: CGSize(width: 1920, height: 1080),
                             frameRate: 30, videoCodec: "H.264", videoBitrate: 8_000_000, dynamicRange: .sdr,
                             audioTracks: [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en")],
                             fileBytes: 100_000_000)
        var settings = EncodeSettings()
        settings.container = .m4a
        let prediction = try #require(OutputEstimate.prediction(info: info, settings: settings))
        // 256 kbit/s for 100 s ≈ 3.2 MB, nowhere near the video's size.
        #expect(prediction.bytes < 4_000_000 && prediction.bytes > 2_000_000)
    }
}
