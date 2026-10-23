import AVFoundation
import Foundation
import Testing
@testable import HyperVideoCore

/// End to end with the real Upscayl backend from Vendor/Upscayl (skipped when it hasn't
/// been fetched with Scripts/fetch-upscayl.sh).
@Suite("Upscale transcodes", .serialized)
struct UpscaleTranscodeTests {
    static var backend: UpscaleBackend? {
        let vendor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/Upscayl")
        return UpscaleBackend(folder: vendor)
    }

    @Test(.enabled(if: backend != nil))
    func upscalesTwiceKeepingAudioAndDuration() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-upscale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 160, height: 90), seconds: 1)

        var settings = EncodeSettings()
        settings.container = .mp4
        var upscale = UpscaleSettings()
        upscale.scale = .x2
        settings.upscale = upscale
        let progress = ProgressLog()
        let engine = TranscodeEngine(upscaleBackend: try #require(Self.backend))
        let output = try await engine.transcode(source: source, destination: dir.appendingPathComponent("out.mp4"),
                                                settings: settings) { progress.add($0) }

        let asset = AVURLAsset(url: output.url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(size == CGSize(width: 320, height: 180))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.1)
        #expect(progress.last == 1)
        // The work folder (frames) is gone.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".hypervideo-") }
        #expect(leftovers.isEmpty)
    }

    /// The model keeps colours; the frame round trip and the encoder must too.
    @Test(.enabled(if: backend != nil))
    func keepsTheSourceColours() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-upscale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 160, height: 90), seconds: 1)
        var settings = EncodeSettings()
        settings.upscale = UpscaleSettings()
        let engine = TranscodeEngine(upscaleBackend: try #require(Self.backend))
        let output = try await engine.transcode(source: source, destination: dir.appendingPathComponent("c.mp4"),
                                                settings: settings) { _ in }
        let before = try await Self.averageColor(of: source)
        let after = try await Self.averageColor(of: output.url)
        for (a, b) in zip(before, after) { #expect(abs(a - b) < 6, "\(before) vs \(after)") }
        let track = try #require(try await AVURLAsset(url: output.url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let matrix = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix)
        #expect(matrix != nil, "the output says which colour matrix it uses")
    }

    /// Mean RGB of the frame at 0.5 s, as AVFoundation decodes it.
    static func averageColor(of url: URL) async throws -> [Double] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        let width = 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<3).map { channel in
            Double(stride(from: channel, to: pixels.count, by: 4).map { Int(pixels[$0]) }.reduce(0, +)) / Double(width * height)
        }
    }

    @Test func missingBackendFailsWithAClearError() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hvc-upscale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 160, height: 90), seconds: 1)
        var settings = EncodeSettings()
        settings.upscale = UpscaleSettings()
        let engine = TranscodeEngine(upscaleBackend: nil)
        await #expect(throws: UpscaleError.self) {
            _ = try await engine.transcode(source: source, destination: dir.appendingPathComponent("o.mp4"),
                                           settings: settings) { _ in }
        }
    }
}
