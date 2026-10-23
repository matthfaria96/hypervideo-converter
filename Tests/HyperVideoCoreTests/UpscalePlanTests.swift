import CoreGraphics
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Upscale plan")
struct UpscalePlanTests {
    static func info(width: Double = 1280, height: Double = 720, fps: Double = 30, seconds: Double = 60,
                     videoBitrate: Double? = 2_000_000, fileBytes: Int64 = 16_000_000) -> MediaInfo {
        MediaInfo(url: URL(fileURLWithPath: "/tmp/clip.mp4"), duration: seconds,
                  displaySize: CGSize(width: width, height: height), frameRate: fps, videoCodec: "H.264",
                  videoBitrate: videoBitrate, dynamicRange: .sdr,
                  audioTracks: [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en")],
                  fileBytes: fileBytes)
    }

    @Test func outputSizeMultipliesTheSource() {
        var settings = UpscaleSettings()
        settings.scale = .x2
        #expect(UpscalePlan(info: Self.info(), settings: settings).outputSize == CGSize(width: 2560, height: 1440))
        settings.scale = .x3
        #expect(UpscalePlan(info: Self.info(), settings: settings).outputSize == CGSize(width: 3840, height: 2160))
    }

    @Test func limitTo4KKeepsTheAspectInsideTheUHDBox() {
        var settings = UpscaleSettings()
        settings.scale = .x4
        settings.limitTo4K = true
        let landscape = UpscalePlan(info: Self.info(width: 1920, height: 1080), settings: settings)
        #expect(landscape.outputSize == CGSize(width: 3840, height: 2160))
        #expect(landscape.isLimited)
        let portrait = UpscalePlan(info: Self.info(width: 1080, height: 1920), settings: settings)
        #expect(portrait.outputSize == CGSize(width: 2160, height: 3840))
        settings.limitTo4K = false
        #expect(UpscalePlan(info: Self.info(width: 1920, height: 1080), settings: settings).outputSize
                == CGSize(width: 7680, height: 4320))
    }

    @Test func dimensionsAreAlwaysEven() {
        var settings = UpscaleSettings()
        settings.scale = .x3
        let plan = UpscalePlan(info: Self.info(width: 641, height: 359), settings: settings)
        #expect(Int(plan.outputSize.width) % 2 == 0 && Int(plan.outputSize.height) % 2 == 0)
    }

    @Test func bitrateFollowsPixelsFrameRateAndWeight() {
        var settings = UpscaleSettings()
        settings.scale = .x2
        settings.weight = .balanced
        settings.codec = .hevc
        let plan = UpscalePlan(info: Self.info(), settings: settings)
        let expected = 2560.0 * 1440 * 30 * UpscaleWeight.balanced.bitsPerPixel(for: .hevc)
        #expect(abs(plan.videoBitrate - expected) < 1)
        settings.weight = .compact
        #expect(UpscalePlan(info: Self.info(), settings: settings).videoBitrate < plan.videoBitrate)
        settings.weight = .balanced
        settings.codec = .h264
        #expect(UpscalePlan(info: Self.info(), settings: settings).videoBitrate > plan.videoBitrate)
    }

    @Test func predictedSizeIsVideoPlusTheCopiedAudio() {
        var settings = UpscaleSettings()
        settings.scale = .x2
        // 60 s at 2 Mbit/s video = 15 MB; the file is 16 MB, so ~1 MB of audio is copied as is.
        let plan = UpscalePlan(info: Self.info(), settings: settings)
        let video = plan.videoBitrate * 60 / 8
        #expect(abs(Double(plan.predictedBytes) - (video + 1_000_000) * UpscalePlan.containerOverhead) < 2)
        #expect(plan.growth > 0)
    }

    @Test func unknownSourceBitrateStillPredicts() {
        let plan = UpscalePlan(info: Self.info(videoBitrate: nil), settings: UpscaleSettings())
        #expect(plan.predictedBytes > 0)
    }

    @Test func fasterModelsPredictShorterTimes() {
        var settings = UpscaleSettings()
        let times = UpscaleModel.allCases.map { model in
            settings.model = model
            return UpscalePlan(info: Self.info(), settings: settings).estimatedSeconds
        }
        let lite = times[UpscaleModel.allCases.firstIndex(of: .lite)!]
        #expect(times.allSatisfy { $0 >= lite })
        // 60 s × 30 fps = 1800 frames of 0.92 MP at the Lite rate.
        #expect(abs(lite - 1800 * 0.9216 * UpscaleModel.lite.secondsPerSourceMegapixel) < 1)
    }

    @Test func liteIsTheDefault() {
        #expect(UpscaleSettings().model == .lite && UpscaleSettings().scale == .x2)
    }
}

@Suite("Upscale settings persistence")
struct UpscaleSettingsPersistenceTests {
    @Test func olderSettingsDecodeWithoutUpscale() throws {
        let data = try JSONEncoder().encode(EncodeSettings())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["upscale"] = nil
        let decoded = try JSONDecoder().decode(EncodeSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.upscale == nil)
    }

    @Test func upscaleRoundTrips() throws {
        var settings = EncodeSettings()
        var upscale = UpscaleSettings()
        upscale.model = .digitalArt
        upscale.scale = .x3
        upscale.weight = .high
        upscale.codec = .h264
        upscale.limitTo4K = false
        settings.upscale = upscale
        let decoded = try JSONDecoder().decode(EncodeSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.upscale == upscale)
    }

    @Test func unknownUpscaleFieldsFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(UpscaleSettings.self, from: Data(#"{"scale": 3}"#.utf8))
        #expect(decoded.scale == .x3 && decoded.model == .lite)
    }
}
