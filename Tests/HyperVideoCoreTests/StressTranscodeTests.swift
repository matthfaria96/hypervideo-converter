@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

/// Unusual real-world sources pushed through the engine end to end.
@Suite("Stress transcodes", .serialized)
struct StressTranscodeTests {
    typealias Spec = StressClip.Spec

    private func encode(_ source: URL, _ settings: EncodeSettings, name: String = "out",
                        subtitleFiles: [SubtitleFile] = []) async throws -> (URL, MediaInfo) {
        let out = source.deletingLastPathComponent().appendingPathComponent("\(name).\(settings.container.fileExtension)")
        let bytes = try await TranscodeEngine().run(source: source, destination: out, settings: settings,
                                                    subtitleFiles: subtitleFiles) { _ in }
        #expect(bytes > 0)
        return (out, try await MediaInspector.inspect(out))
    }

    /// Video and audio track durations of `url`, to check they stay in sync.
    private func trackDurations(_ url: URL) async throws -> (video: Double?, audio: [Double]) {
        let asset = AVURLAsset(url: url)
        var video: Double?
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            video = try await track.load(.timeRange).duration.seconds
        }
        var audio: [Double] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            audio.append(try await track.load(.timeRange).duration.seconds)
        }
        return (video, audio)
    }

    @Test(arguments: [VideoCodec.h264, .hevc])
    func oddDimensionsBecomeEven(codec: VideoCodec) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(size: CGSize(width: 721, height: 405)))
        var settings = EncodeSettings()
        settings.videoCodec = codec
        settings.crop = Crop(top: 3, bottom: 0, left: 5, right: 0)
        let (out, info) = try await encode(source, settings)
        let size = try #require(try await MediaInspector.inspect(source).displaySize)
        #expect(info.displaySize == CGSize(width: GeometryPlanner.even(size.width - 5), height: GeometryPlanner.even(size.height - 3)))
        #expect(abs(info.duration - 1) < 0.1)
        let tracks = try await trackDurations(out)
        #expect(abs((tracks.video ?? 0) - (tracks.audio.first ?? -1)) < 0.1)
    }

    @Test func iPhonePortraitRotationIsApplied() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        let source = try await StressClip.make(in: dir, Spec(size: CGSize(width: 640, height: 360), transform: transform))
        #expect(try await MediaInspector.inspect(source).displaySize == CGSize(width: 360, height: 640))

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.maxResolution = .sd480
        let (_, info) = try await encode(source, settings)
        #expect(info.displaySize == CGSize(width: 360, height: 640))

        settings.videoCodec = .passthrough
        settings.maxResolution = .source
        settings.container = .mov
        let (_, copied) = try await encode(source, settings, name: "copy")
        #expect(copied.displaySize == CGSize(width: 360, height: 640))
    }

    @Test func variableFrameRateKeepsDuration() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        // 2 s: dense frames at first, then sparse ones.
        let times = (0..<40).map { Double($0) / 40 } + (0..<10).map { 1 + Double($0) / 10 }
        let source = try await StressClip.make(in: dir, Spec(frameTimes: times, seconds: 2))
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        let (out, info) = try await encode(source, settings)
        #expect(abs(info.duration - 2) < 0.15, "\(info.duration)")
        let tracks = try await trackDurations(out)
        #expect(abs((tracks.video ?? 0) - 2) < 0.15, "\(tracks)")
    }

    @Test func tenBitHEVCAndProResSources() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let hevc = try await StressClip.make(in: dir, Spec(name: "hevc10", codec: .hevc, tenBit: true))
        let prores = try await StressClip.make(in: dir, Spec(name: "prores", codec: .proRes422))
        for (source, codec) in [(hevc, VideoCodec.h264), (hevc, .hevc10), (prores, .hevc), (prores, .proRes422)] {
            var settings = EncodeSettings()
            settings.videoCodec = codec
            settings.container = codec.isProRes ? .mov : .mp4
            let (_, info) = try await encode(source, settings, name: "\(source.lastPathComponent)-\(codec.rawValue)")
            #expect(info.displaySize == CGSize(width: 320, height: 180))
            #expect(abs(info.duration - 1) < 0.1)
            #expect(info.audioTracks.count == 1)
        }
    }

    @Test func noAudioSource() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(audio: []))
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.extraAudio = AudioEncoding(codec: .aac, mixdown: .mono, bitrateKbps: 64)
        let (_, info) = try await encode(source, settings)
        #expect(info.audioTracks.isEmpty)
        #expect(abs(info.duration - 1) < 0.1)
    }

    @Test(arguments: [ContainerFormat.mp4, .mov, .m4v])
    func audioOnlySource(container: ContainerFormat) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(fileType: .mp4, size: nil, seconds: 1.5))
        var settings = EncodeSettings()
        settings.container = container
        settings.trim = TrimRange(start: 0.5, end: nil)
        let (_, info) = try await encode(source, settings)
        #expect(info.displaySize == nil)
        #expect(info.audioTracks.count == 1)
        #expect(abs(info.duration - 1) < 0.1, "\(info.duration)")
    }

    @Test func audioOnlyWithAudioDisabledFailsClearly() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(size: nil))
        var settings = EncodeSettings()
        settings.audioCodec = .none
        await #expect(throws: TranscodeError.self) {
            _ = try await encode(source, settings)
        }
    }

    @Test func surroundAndMultipleTracksAndLowRateMono() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(audio: [
            .init(channels: 6, language: "en"), .init(channels: 1, sampleRate: 8_000, language: "fr"), .init(language: "de")
        ]))
        let sourceInfo = try await MediaInspector.inspect(source)
        #expect(sourceInfo.audioTracks.map(\.channels) == [6, 1, 2])

        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.audioTracks = .all
        settings.audioMixdown = .surround51
        settings.audioBitrateKbps = 384
        settings.extraAudio = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 128)
        let (out, info) = try await encode(source, settings)
        #expect(info.audioTracks.map(\.channels) == [6, 2, 1, 1, 2, 2])
        #expect(info.audioTracks.map(\.language) == ["en", "en", "fr", "fr", "de", "de"])
        let tracks = try await trackDurations(out)
        for audio in tracks.audio { #expect(abs(audio - (tracks.video ?? 0)) < 0.1, "\(tracks)") }

        settings.audioCodec = .alac
        settings.extraAudio = nil
        settings.container = .mov
        let (_, lossless) = try await encode(source, settings, name: "alac")
        #expect(lossless.audioTracks.map(\.codec) == ["ALAC", "ALAC", "ALAC"])
        #expect(lossless.audioTracks.map(\.channels) == [6, 1, 2])

        settings.audioCodec = .passthrough
        let (_, copied) = try await encode(source, settings, name: "copy")
        #expect(copied.audioTracks.map(\.channels) == [6, 1, 2])
    }

    @Test func veryShortClips() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(frameTimes: (0..<6).map { Double($0) / 30 }, seconds: 0.2))
        for codec in [VideoCodec.h264, .hevc, .proRes422] {
            var settings = EncodeSettings()
            settings.videoCodec = codec
            settings.container = .mov
            settings.filters.denoise = .light
            let (_, info) = try await encode(source, settings, name: codec.rawValue)
            #expect(abs(info.duration - 0.2) < 0.05, "\(codec) \(info.duration)")
        }
        var settings = EncodeSettings()
        settings.trim = TrimRange(start: 0.1, end: 0.15)
        let (_, trimmed) = try await encode(source, settings, name: "trimmed")
        #expect(trimmed.duration < 0.15)
    }

    @Test func filtersWithCropRotateAndTrim() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, Spec(size: CGSize(width: 721, height: 405),
                                                              frameTimes: (0..<60).map { Double($0) / 30 }, seconds: 2))
        var settings = EncodeSettings()
        settings.videoCodec = .hevc
        settings.container = .mov
        settings.rotation = .cw270
        settings.flipHorizontal = true
        settings.crop = Crop(top: 10, bottom: 11, left: 0, right: 0)
        settings.filters.grayscale = true
        settings.filters.sharpen = .medium
        settings.filters.deinterlace = .always
        settings.frameRate = .fps25
        settings.trim = TrimRange(start: 0.5, end: 1.5)
        let (out, info) = try await encode(source, settings)
        // The H.264 encoder may round the odd source size down, so derive from what it wrote.
        let size = try #require(try await MediaInspector.inspect(source).displaySize)
        #expect(info.displaySize == CGSize(width: GeometryPlanner.even(size.height), height: GeometryPlanner.even(size.width - 21)))
        #expect(abs(info.duration - 1) < 0.1)
        let tracks = try await trackDurations(out)
        #expect(abs((tracks.video ?? 0) - (tracks.audio.first ?? -1)) < 0.1, "\(tracks)")
    }

    @Test func embeddedTextAndSidecarAndChaptersInMOV() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await SyntheticClip.make(in: dir, size: CGSize(width: 320, height: 180), seconds: 3,
                                                  subtitleLanguages: ["en"], chapters: ["A", "B", "C"])
        let srt = dir.appendingPathComponent("side.srt")
        try "1\n00:00:00,500 --> 00:00:02,000\nOlá\n".write(to: srt, atomically: true, encoding: .utf8)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.container = .mov
        settings.trim = TrimRange(start: 1, end: nil)
        let (_, info) = try await encode(source, settings, subtitleFiles: [SubtitleFile(url: srt, language: "pt")])
        #expect(info.subtitleTracks.map(\.language) == ["en", "pt"])
        #expect(info.chapters.map(\.title) == ["B", "C"])
        #expect(abs(info.duration - 2) < 0.1)
    }

    @Test func corruptAndMissingSourcesFailWithTranscodeError() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let good = try await StressClip.make(in: dir, Spec(frameTimes: (0..<60).map { Double($0) / 30 }, seconds: 2))
        let data = try Data(contentsOf: good)
        let truncated = dir.appendingPathComponent("truncated.mov")
        try data.prefix(data.count / 2).write(to: truncated)
        let garbage = dir.appendingPathComponent("garbage.mp4")
        try Data((0..<4_096).map { UInt8($0 % 251) }).write(to: garbage)
        let missing = dir.appendingPathComponent("missing.mov")
        for source in [truncated, garbage, missing] {
            let started = ContinuousClock.now
            await #expect(throws: TranscodeError.self, "\(source.lastPathComponent)") {
                _ = try await encode(source, EncodeSettings(), name: "o-\(source.lastPathComponent)")
            }
            #expect(ContinuousClock.now - started < .seconds(20))
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("o-") || $0.hasPrefix(".") }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    @Test func nonASCIIPathsWithSpaces() async throws {
        let dir = try TranscodeIntegrationTests.tempDir().appendingPathComponent("Fériàs 2026 ☀︎ 日本")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try await StressClip.make(in: dir, Spec(name: "Vídeo de Ação #1 (çã)"))
        let srt = dir.appendingPathComponent("Vídeo de Ação #1 (çã).pt-BR.srt")
        try "1\n00:00:00,000 --> 00:00:00,800\nOi\n".write(to: srt, atomically: true, encoding: .utf8)
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        let (out, info) = try await encode(source, settings, name: "Saída — final",
                                           subtitleFiles: SubtitleFile.sidecars(for: source))
        #expect(out.lastPathComponent == "Saída — final.mp4")
        #expect(info.subtitleTracks.map(\.language) == ["pt-BR"])
    }

    @Test func mismatchedTrackLengthsAndLateFirstFrame() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        // Video covers 0.5–1.5 s, audio runs 0–2 s.
        let source = try await StressClip.make(in: dir, Spec(frameTimes: (15..<45).map { Double($0) / 30 }, seconds: 2))
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        let (out, info) = try await encode(source, settings)
        #expect(abs(info.duration - 2) < 0.1, "\(info.duration)")
        let tracks = try await trackDurations(out)
        #expect(abs((tracks.audio.first ?? 0) - 2) < 0.1, "\(tracks)")

        settings.trim = TrimRange(start: 1.6, end: nil)
        let (_, tail) = try await encode(source, settings, name: "tail")
        #expect(abs(tail.duration - 0.4) < 0.1, "\(tail.duration)")
    }
}
