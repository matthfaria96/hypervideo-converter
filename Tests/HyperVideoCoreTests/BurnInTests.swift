@preconcurrency import AVFoundation
import CoreText
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Subtitle burn-in")
struct BurnInTests {
    @Test func passthroughVideoCantBurnIn() {
        var settings = EncodeSettings()
        settings.burnIn = .track(id: 3)
        #expect(settings.isValid)
        settings.videoCodec = .passthrough
        #expect(settings.validationIssues.contains { $0.contains("Burned-in subtitles") })
    }

    @Test func burnInSurvivesCoding() throws {
        var settings = EncodeSettings()
        settings.burnIn = .file(URL(fileURLWithPath: "/tmp/a.srt"))
        let decoded = try JSONDecoder().decode(EncodeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.burnIn == settings.burnIn)
    }

    @Test func rendererDrawsBottomCenteredTextThatWraps() throws {
        let size = CGSize(width: 640, height: 360)
        let image = try #require(SubtitleBurner.render("Hello", size: size))
        let pixels = Self.rgba(image)
        // Opaque pixels sit only in the bottom third, horizontally around the middle.
        var rows: [Int] = [], columns: [Int] = []
        for y in 0..<image.height { for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 128 {
            rows.append(y); columns.append(x)
        } }
        #expect(!rows.isEmpty)
        // CGImage rows run top to bottom.
        #expect(rows.min()! > image.height * 2 / 3)
        let center = Double(columns.min()! + columns.max()!) / 2
        #expect(abs(center - Double(image.width) / 2) < 20)

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil)
        ]
        let short = SubtitleBurner.textBox("Short", attributes: attributes, size: size)
        let long = SubtitleBurner.textBox(String(repeating: "A long subtitle line ", count: 8), attributes: attributes, size: size)
        #expect(long.height > short.height * 2)
        #expect(long.width <= size.width)
    }

    @Test func overlayFollowsCueTimes() {
        let burner = SubtitleBurner(cues: [SubtitleCue(start: 1, end: 2, text: "Hi")], start: 0, end: 5)
        let size = CGSize(width: 64, height: 36)
        #expect(burner.overlay(at: 0.5, size: size) == nil)
        #expect(burner.overlay(at: 1.5, size: size) != nil)
        #expect(burner.overlay(at: 2.5, size: size) == nil)
    }

    /// Encodes with and without a burned SRT cue (source 2–3 s) on a 1–4 s trim, then
    /// compares the subtitle region of matching frames: different during the cue only.
    @Test func burnedFileCueAppearsOnlyDuringItsTimeInTrimmedOutput() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 640, height: 360), seconds: 4)
        let srt = dir.appendingPathComponent("cue.srt")
        try "1\n00:00:02,000 --> 00:00:03,000\nBurned subtitle\n".write(to: srt, atomically: true, encoding: .utf8)

        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 1, end: 4)
        let plain = dir.appendingPathComponent("plain.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: plain, settings: settings) { _ in }
        settings.burnIn = .file(srt)
        let burned = dir.appendingPathComponent("burned.mp4")
        let files = [SubtitleFile(url: srt, language: "en")]
        _ = try await TranscodeEngine().run(source: source, destination: burned, settings: settings, subtitleFiles: files) { _ in }

        // Output time 1.5 s is source 2.5 s (inside the cue); 0.5 and 2.5 are outside.
        let during = try await Self.regionDifference(plain, burned, at: 1.5)
        let before = try await Self.regionDifference(plain, burned, at: 0.5)
        let after = try await Self.regionDifference(plain, burned, at: 2.5)
        #expect(during > 0.01, "during \(during)")
        #expect(before < 0.001, "before \(before)")
        #expect(after < 0.001, "after \(after)")
        // The burned file isn't also kept as a soft track.
        #expect(try await MediaInspector.inspect(burned).subtitleTracks.isEmpty)
    }

    @Test func burnedSourceTrackIsDroppedFromSoftTracks() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 2,
                                                  subtitleLanguages: ["en", "fr"])
        let tracks = try await MediaInspector.inspect(source).subtitleTracks
        var settings = EncodeSettings()
        settings.burnIn = .track(id: try #require(tracks.first?.id))
        let out = dir.appendingPathComponent("out.mp4")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        #expect(try await MediaInspector.inspect(out).subtitleTracks.map(\.language) == ["fr"])

        let plain = dir.appendingPathComponent("plain.mp4")
        settings.burnIn = nil
        _ = try await TranscodeEngine().run(source: source, destination: plain, settings: settings) { _ in }
        #expect(try await Self.regionDifference(plain, out, at: 0.5) > 0.01)
    }

    // MARK: Helpers

    /// The share of pixels in the bottom fifth of two videos' frames at `seconds` whose
    /// color differs clearly (by more than 64 on average across RGB); encoder noise stays below that.
    static func regionDifference(_ a: URL, _ b: URL, at seconds: Double) async throws -> Double {
        let first = rgba(try await frame(a, at: seconds))
        let second = rgba(try await frame(b, at: seconds))
        let image = try await frame(a, at: seconds)
        let width = image.width, height = image.height
        var changed = 0, count = 0
        for y in (height * 4 / 5)..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let delta = (0..<3).reduce(0) { $0 + abs(Int(first[i + $1]) - Int(second[i + $1])) }
                if delta > 192 { changed += 1 }
                count += 1
            }
        }
        return Double(changed) / Double(count)
    }

    static func frame(_ url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
