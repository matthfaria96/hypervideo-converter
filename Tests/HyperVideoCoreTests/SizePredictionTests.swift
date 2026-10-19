import CoreGraphics
import Foundation
import Testing
@testable import HyperVideoCore

@Suite("Size predictions")
struct SizePredictionTests {
    let info = MediaInfo(url: URL(fileURLWithPath: "/a.mov"), duration: 100, displaySize: CGSize(width: 3840, height: 2160),
                         frameRate: 30, videoCodec: "ProRes", videoBitrate: nil, dynamicRange: .sdr,
                         audioTracks: [AudioTrackInfo(id: 2, codec: "AAC", channels: 2, sampleRate: 48_000, language: nil)],
                         fileBytes: 5_000_000_000)

    @Test func constantQualityUsesBitsPerPixel() throws {
        var settings = QualityProfile.balanced.settings
        settings.maxResolution = .fhd1080
        let prediction = try #require(OutputEstimate.prediction(info: info, settings: settings))
        #expect(prediction.kind == .approximate)
        let bpp = OutputEstimate.bitsPerPixel(codec: .h264, quality: 0.62)
        let expected = ((bpp * 1920 * 1080 * 30) + 160_000) * 100 / 8
        #expect(abs(Double(prediction.bytes) - expected) < 2)
    }

    @Test func higherQualityAndH264AreLarger() throws {
        func bytes(_ profile: QualityProfile, compress: Bool = false) throws -> Int64 {
            try #require(OutputEstimate.prediction(info: info, settings: profile.settings(compress: compress))).bytes
        }
        #expect(try bytes(.highQuality) > bytes(.balanced))
        #expect(try bytes(.balanced) > bytes(.smallerFile))
        #expect(try bytes(.balanced) > bytes(.balanced, compress: true))
    }

    @Test func neverAboveTheSourceRate() throws {
        var lowRate = info
        lowRate.videoBitrate = 1_000_000
        let prediction = try #require(OutputEstimate.prediction(info: lowRate, settings: QualityProfile.keepOriginal.settings))
        #expect(prediction.bytes <= Int64((1_000_000 + 160_000) * 100 / 8) + 1)
    }

    @Test func averageBitrateIsAnUpperBound() throws {
        var settings = QualityProfile.balanced.settings
        settings.rateControl = .averageBitrate(2_000)
        #expect(OutputEstimate.prediction(info: info, settings: settings)?.kind == .upTo)
    }

    @Test func jobsSavedWithoutPresetIDStillDecode() throws {
        let job = EncodeJob(source: URL(fileURLWithPath: "/a.mov"), destination: URL(fileURLWithPath: "/b.mp4"),
                            settings: EncodeSettings(), presetName: "Fast", presetID: QualityProfile.balanced.presetID)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as! [String: Any]
        #expect(legacy["presetID"] != nil)
        legacy.removeValue(forKey: "presetID")
        let decoded = try JSONDecoder().decode(EncodeJob.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.presetID == nil && decoded.presetName == "Fast")
    }

    @Test func compressProfilesHaveTheirOwnIdentity() {
        for profile in QualityProfile.allCases {
            #expect(profile.compressPresetID != profile.presetID)
            #expect(QualityProfile.profile(presetID: profile.compressPresetID) == profile)
            #expect(QualityProfile.isCompressPreset(profile.compressPresetID))
        }
        #expect(QualityProfile.compressSettings.videoCodec == .hevc)
    }
}
