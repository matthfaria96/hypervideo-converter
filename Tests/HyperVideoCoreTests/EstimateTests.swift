import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Encode rate")
struct EncodeRateTests {
    @Test func speedFpsAndRemainingTime() throws {
        // 30 s of 25 fps video, 40% done after 4 s of work.
        let rate = EncodeRate(progress: 0.4, elapsed: 4, mediaDuration: 30, frameRate: 25)
        #expect(try #require(rate.speed) == 3)
        #expect(try #require(rate.framesPerSecond) == 75)
        #expect(abs(try #require(rate.remaining) - 6) < 1e-9)
    }

    @Test func noGuessesRightAfterStart() {
        let rate = EncodeRate(progress: 0.001, elapsed: 0.3, mediaDuration: 30, frameRate: 25)
        #expect(rate.remaining == nil)
        #expect(rate.speed == nil)
    }

    @Test func unknownDurationStillGivesRemainingTime() {
        let rate = EncodeRate(progress: 0.5, elapsed: 10, mediaDuration: nil, frameRate: nil)
        #expect(rate.speed == nil && rate.framesPerSecond == nil)
        #expect(rate.remaining == 10)
    }

    @Test func jobsSavedWithoutRateFieldsStillDecode() throws {
        let job = EncodeJob(source: URL(fileURLWithPath: "/a.mov"), destination: URL(fileURLWithPath: "/b.mp4"),
                            settings: EncodeSettings(), presetName: "Fast")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
        legacy.removeValue(forKey: "mediaDuration")
        legacy.removeValue(forKey: "frameRate")
        let decoded = try JSONDecoder().decode(EncodeJob.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.mediaDuration == nil && decoded.presetName == "Fast")
    }
}

@Suite("Output estimates")
struct OutputEstimateTests {
    let info = MediaInfo(
        url: URL(fileURLWithPath: "/clip.mov"), duration: 100, displaySize: CGSize(width: 1920, height: 1080),
        frameRate: 30, videoCodec: "H.264", videoBitrate: 8_000_000, dynamicRange: .sdr,
        audioTracks: [
            AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: "en", bitrate: 192_000),
            AudioTrackInfo(id: 3, codec: "AAC", channels: 2, sampleRate: 48_000, language: "fr", bitrate: 128_000)
        ],
        fileBytes: 102_400_000
    )

    @Test func outputDurationFollowsTrim() {
        var settings = EncodeSettings()
        #expect(settings.outputDuration(sourceDuration: 100) == 100)
        settings.trim = TrimRange(start: 10, end: 40)
        #expect(settings.outputDuration(sourceDuration: 100) == 30)
        settings.trim = TrimRange(start: 90, end: nil)
        #expect(settings.outputDuration(sourceDuration: 100) == 10)
    }

    @Test func averageBitrateIncludesAllKeptAudio() throws {
        var settings = EncodeSettings()
        settings.rateControl = .averageBitrate(4_000)
        settings.audioCodec = .aac
        settings.audioBitrateKbps = 160
        settings.audioTracks = .all
        // (4000 + 2 × 160) kbit/s for 100 s
        #expect(try #require(OutputEstimate.bytes(info: info, settings: settings)) == 54_000_000)
    }

    @Test func passthroughAudioUsesSourceBitrate() throws {
        var settings = EncodeSettings()
        settings.rateControl = .averageBitrate(4_000)
        settings.audioCodec = .passthrough
        settings.audioTracks = .first
        settings.trim = TrimRange(start: 0, end: 50)
        #expect(try #require(OutputEstimate.bytes(info: info, settings: settings)) == 26_200_000)
    }

    @Test func passthroughVideoScalesSourceSize() throws {
        var settings = EncodeSettings()
        settings.videoCodec = .passthrough
        settings.trim = TrimRange(start: 0, end: 25)
        #expect(try #require(OutputEstimate.bytes(info: info, settings: settings)) == 25_600_000)
    }

    @Test func constantQualityIsUnpredictable() {
        #expect(OutputEstimate.bytes(info: info, settings: EncodeSettings()) == nil)
    }
}
