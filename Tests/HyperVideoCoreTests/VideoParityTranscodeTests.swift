@preconcurrency import AVFoundation
import Testing
@testable import HyperVideoCore

@Suite("Video parity transcodes", .serialized)
struct VideoParityTranscodeTests {
    private func encode(_ source: URL, _ settings: EncodeSettings, name: String = "out") async throws -> URL {
        let ext = settings.container == .mp4 ? "mp4" : "mov"
        let out = source.deletingLastPathComponent().appendingPathComponent("\(name).\(ext)")
        _ = try await TranscodeEngine().run(source: source, destination: out, settings: settings) { _ in }
        return out
    }

    private func settings(
        container: ContainerFormat = .mp4, codec: VideoCodec = .h264, rate: FrameRate = .source,
        mode: FrameRateMode = .constant
    ) -> EncodeSettings {
        var s = EncodeSettings()
        s.container = container
        s.videoCodec = codec
        s.frameRate = rate
        s.videoOptions.frameRateMode = mode
        return s
    }

    private func spacing(_ times: [Double]) -> [Double] { zip(times, times.dropFirst()).map { $1 - $0 } }

    // MARK: Framerate

    @Test func constantRetimesToUniformSpacing() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(frameTimes: (0..<120).map { Double($0) / 60 }))
        let times = try await OutputProbe.presentationTimes(try await encode(source, settings(rate: .fps30)))
        #expect(abs(times.count - 60) <= 2, "\(times.count)")
        for gap in spacing(times) { #expect(abs(gap - 1.0 / 30) < 0.001, "\(gap)") }
    }

    @Test func variableKeepsSourceTiming() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let stamps = [0, 0.1, 0.15, 0.4, 0.45, 0.9, 1.0, 1.05, 1.5, 1.6]
        let source = try await ParityClip.make(in: dir, .init(frameTimes: stamps))
        let times = try await OutputProbe.presentationTimes(try await encode(source, settings(rate: .fps30, mode: .variable)))
        #expect(times.count == stamps.count, "\(times)")
        for (out, expected) in zip(times, stamps) { #expect(abs(out - expected) < 0.002, "\(times)") }
    }

    @Test func peakCapsHighRatesAndKeepsLowOnes() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let fast = try await ParityClip.make(in: dir, .init(name: "fast", frameTimes: (0..<120).map { Double($0) / 60 }))
        let capped = try await OutputProbe.presentationTimes(try await encode(fast, settings(rate: .fps30, mode: .peak)))
        #expect(capped.count <= 62, "\(capped.count)")
        for gap in spacing(capped) { #expect(gap >= 1.0 / 30 - 0.001, "\(gap)") }
        let slow = try await ParityClip.make(in: dir, .init(name: "slow", frameTimes: (0..<48).map { Double($0) / 24 }))
        let kept = try await OutputProbe.presentationTimes(try await encode(slow, settings(rate: .fps30, mode: .peak), name: "slow-out"))
        #expect(kept.count == 48, "\(kept.count)")
    }

    @Test(arguments: FrameRate.allCases.filter { $0 != .source })
    func everyFrameRateEncodes(rate: FrameRate) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 160, height: 90), frameTimes: (0..<120).map { Double($0) / 120 }))
        let out = try await encode(source, settings(rate: rate))
        let info = try await MediaInspector.inspect(out)
        #expect(abs((info.frameRate ?? 0) - rate.rawValue) <= 1, "\(String(describing: info.frameRate)) vs \(rate.rawValue)")
    }

    // MARK: Encoder options

    @Test func speedProfileAndLevelEncode() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init())
        var s = settings()
        s.videoOptions.speed = .quality
        s.videoOptions.profile = .baseline
        s.videoOptions.level = .l31
        s.allowBFrames = false
        let info = try await MediaInspector.inspect(try await encode(source, s))
        #expect(info.videoCodec == "H.264")
    }

    @Test(arguments: [(VideoCodec.proRes422LT, "apcs"), (VideoCodec.proRes422Proxy, "apco")])
    func proResLightVariants(codec: VideoCodec, fourCC: String) async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init())
        let out = try await encode(source, settings(container: .mov, codec: codec))
        let format = try #require(try await OutputProbe.format(out))
        #expect(FourCC.string(CMFormatDescriptionGetMediaSubType(format)).lowercased().contains(fourCC) ||
                CMFormatDescriptionGetMediaSubType(format) == (codec == .proRes422LT ? kCMVideoCodecType_AppleProRes422LT : kCMVideoCodecType_AppleProRes422Proxy))
    }

    // MARK: Picture

    @Test func automaticCropRemovesBlackBars() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(blackBars: 20))
        var s = settings()
        s.pictureOptions.cropMode = .automatic
        let cropped = try await MediaInspector.inspect(try await encode(source, s))
        #expect(cropped.displaySize == CGSize(width: 320, height: 140))
        s.pictureOptions.cropMode = .none
        let full = try await MediaInspector.inspect(try await encode(source, s, name: "none"))
        #expect(full.displaySize == CGSize(width: 320, height: 180))
        s.pictureOptions.cropMode = .custom
        let custom = try await MediaInspector.inspect(try await encode(source, s, name: "custom"))
        #expect(custom.displaySize == CGSize(width: 320, height: 180))
    }

    @Test func upscalingPlansTheBiggerPicture() async throws {
        let big = GeometryPlanner.plan(
            naturalSize: CGSize(width: 960, height: 540), preferredTransform: .identity, crop: .zero, rotation: .none,
            flipHorizontal: false, maxResolution: .uhd4320, picture: { var p = PictureOptions(); p.allowUpscaling = true; return p }()
        )
        #expect(big.renderSize == CGSize(width: 7680, height: 4320))
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 640, height: 360)))
        var s = settings()
        s.maxResolution = .fhd1080
        s.pictureOptions.allowUpscaling = true
        let info = try await MediaInspector.inspect(try await encode(source, s))
        #expect(info.displaySize == CGSize(width: 1920, height: 1080))
    }

    @Test func letterboxPaddingUsesTheChosenColor() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 640, height: 272)))
        var s = settings()
        s.pictureOptions.padding = Padding(mode: .letterbox, color: .white)
        let out = try await encode(source, s)
        #expect(try await MediaInspector.inspect(out).displaySize == CGSize(width: 640, height: 360))
        #expect(try await OutputProbe.rowLuma(out, time: 0.3, rowFraction: 0.03) > 200)
        let centre = try await OutputProbe.rowLuma(out, time: 0.3, rowFraction: 0.5)
        #expect(centre < 200, "\(centre)")
    }

    @Test func filteredPathPadsToo() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 640, height: 272)))
        var s = settings()
        s.filters.grayscale = true
        s.pictureOptions.padding = Padding(mode: .letterbox, color: .white)
        let out = try await encode(source, s)
        #expect(try await OutputProbe.rowLuma(out, time: 0.3, rowFraction: 0.03) > 200)
        #expect(try await OutputProbe.rowLuma(out, time: 0.3, rowFraction: 0.5) < 200)
    }

    @Test func colorspaceTargetTagsTheOutput() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init())
        var s = settings()
        s.filters.colorspace = .bt601ntsc
        let format = try #require(try await OutputProbe.format(try await encode(source, s)))
        #expect(MediaInspector.colorSpace(of: format)?.primaries == AVVideoColorPrimaries_SMPTE_C)
    }

    @Test func anamorphicAutomaticTagsPixelAspect() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 480, height: 360), pixelAspect: CGSize(width: 4, height: 3)))
        let sourceFormat = try #require(try await OutputProbe.format(source))
        #expect(OutputProbe.pixelAspect(sourceFormat) == CGSize(width: 4, height: 3))
        var s = settings()
        s.pictureOptions.anamorphic = .automatic
        let out = try await encode(source, s)
        let format = try #require(try await OutputProbe.format(out))
        #expect(OutputProbe.pixelAspect(format) == CGSize(width: 4, height: 3))
        let before = try await MediaInspector.inspect(source).displaySize ?? .zero
        let after = try await MediaInspector.inspect(out).displaySize ?? .zero
        #expect(abs(after.width / after.height - before.width / before.height) / (before.width / before.height) < 0.01,
                "\(before) -> \(after)")
    }

    /// Probe result (recorded in the 03.1-03 summary): AVFoundation reports the display size
    /// (storage width x pixel aspect) as `naturalSize` for a pixel-aspect-tagged track.
    @Test func naturalSizeOfTaggedClipIsDisplaySize() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await ParityClip.make(in: dir, .init(size: CGSize(width: 480, height: 360), pixelAspect: CGSize(width: 4, height: 3)))
        let info = try await MediaInspector.inspect(source)
        #expect(info.displaySize == CGSize(width: 640, height: 360))
    }

    // MARK: Timing

    @Test func alignAVStartRemovesTheLeadIn() async throws {
        let dir = try TranscodeIntegrationTests.tempDir()
        let source = try await StressClip.make(in: dir, StressClip.Spec(frameTimes: (15..<45).map { Double($0) / 30 }, seconds: 2))
        var s = settings()
        let off = try await MediaInspector.inspect(try await encode(source, s))
        #expect(abs(off.duration - 2) < 0.1, "\(off.duration)")
        s.alignAVStart = true
        let on = try await MediaInspector.inspect(try await encode(source, s, name: "aligned"))
        // The 0.5 s before the first video frame is cut from the audio as well as the picture.
        #expect(abs(on.duration - 1.5) < 0.1, "\(on.duration)")
    }
}
