import AVFoundation
import Testing
import VideoToolbox
@testable import HyperVideoCore

@Suite("Video encoder settings")
struct VideoEncoderSettingsTests {
    @Test func defaultCompressionKeysAreUnchanged() {
        let props = OutputSettingsBuilder.compression(settings: EncodeSettings(), sourceFrameRate: 30)
        #expect(props[AVVideoExpectedSourceFrameRateKey] as? Double == 30)
        #expect(props[AVVideoMaxKeyFrameIntervalDurationKey] as? Double == 2)
        #expect(props[AVVideoAllowFrameReorderingKey] as? Bool == true)
        #expect(props[AVVideoProfileLevelKey] as? String == kVTProfileLevel_HEVC_Main_AutoLevel as String)
        #expect(props[AVVideoQualityKey] as? Double == 0.62)
        #expect(props[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] == nil)
    }

    @Test func baselineNeverReordersFrames() {
        var settings = EncodeSettings()
        settings.videoCodec = .h264
        settings.allowBFrames = true
        settings.videoOptions.profile = .baseline
        let baseline = OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 30)
        #expect(baseline[AVVideoAllowFrameReorderingKey] as? Bool == false)
        settings.videoOptions.profile = .main
        let main = OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 30)
        #expect(main[AVVideoAllowFrameReorderingKey] as? Bool == true)
    }

    @Test func speedMapsToEncoderKeys() {
        var settings = EncodeSettings()
        settings.videoOptions.speed = .speed
        let fast = OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 30)
        #expect(fast[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] as? Bool == true)
        settings.videoOptions.speed = .quality
        let slow = OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 30)
        #expect(slow[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] as? Bool == false)
        #expect(slow[kVTCompressionPropertyKey_MaximizePowerEfficiency as String] as? Bool == false)
    }

    @Test func h264ProfileAndLevel() {
        typealias B = OutputSettingsBuilder
        #expect(B.profileLevel(codec: .h264, profile: .auto, level: .auto) == AVVideoProfileLevelH264HighAutoLevel)
        #expect(B.profileLevel(codec: .h264, profile: .baseline, level: .auto) == AVVideoProfileLevelH264BaselineAutoLevel)
        #expect(B.profileLevel(codec: .h264, profile: .main, level: .l31) == kVTProfileLevel_H264_Main_3_1 as String)
        #expect(B.profileLevel(codec: .h264, profile: .high, level: .l41) == kVTProfileLevel_H264_High_4_1 as String)
        #expect(B.profileLevel(codec: .h264, profile: .auto, level: .l40) == kVTProfileLevel_H264_High_4_0 as String)
    }

    @Test func hevcProfiles() {
        typealias B = OutputSettingsBuilder
        #expect(B.profileLevel(codec: .hevc, profile: .main10, level: .l41) == kVTProfileLevel_HEVC_Main_AutoLevel as String)
        #expect(B.profileLevel(codec: .hevc10, profile: .auto, level: .auto) == kVTProfileLevel_HEVC_Main10_AutoLevel as String)
    }

    @Test func proResLightVariants() {
        #expect(OutputSettingsBuilder.codecType(.proRes422LT) == .proRes422LT)
        #expect(OutputSettingsBuilder.codecType(.proRes422Proxy) == .proRes422Proxy)
    }

    @Test func pixelAspectKey() {
        let settings = EncodeSettings()
        let wide = OutputSettingsBuilder.video(
            settings: settings, renderSize: CGSize(width: 640, height: 480), sourceFrameRate: 30,
            color: .rec709, pixelAspect: CGSize(width: 4, height: 3)
        )
        let par = wide[AVVideoPixelAspectRatioKey] as? [String: Int]
        #expect(par?[AVVideoPixelAspectRatioHorizontalSpacingKey] == 4)
        #expect(par?[AVVideoPixelAspectRatioVerticalSpacingKey] == 3)
        for aspect in [nil, CGSize(width: 1, height: 1)] {
            let square = OutputSettingsBuilder.video(
                settings: settings, renderSize: CGSize(width: 640, height: 480), sourceFrameRate: 30,
                color: .rec709, pixelAspect: aspect
            )
            #expect(square[AVVideoPixelAspectRatioKey] == nil)
        }
    }

    @Test func colorspaceTargets() {
        typealias B = OutputSettingsBuilder
        #expect(B.outputColorSpace(for: .h264, source: nil, target: .off) == .rec709)
        let ntsc = B.outputColorSpace(for: .h264, source: nil, target: .bt601ntsc)
        #expect(ntsc.primaries == AVVideoColorPrimaries_SMPTE_C)
        #expect(ntsc.transfer == AVVideoTransferFunction_ITU_R_709_2)
        #expect(ntsc.matrix == AVVideoYCbCrMatrix_ITU_R_601_4)
        let pal = B.outputColorSpace(for: .h264, source: nil, target: .bt601pal)
        #expect(pal.primaries == AVVideoColorPrimaries_EBU_3213)
        #expect(pal.matrix == AVVideoYCbCrMatrix_ITU_R_601_4)
        let wide = B.outputColorSpace(for: .h264, source: nil, target: .bt2020)
        #expect(wide.primaries == AVVideoColorPrimaries_ITU_R_2020)
        #expect(wide.transfer == AVVideoTransferFunction_ITU_R_709_2)
        #expect(wide.matrix == AVVideoYCbCrMatrix_ITU_R_2020)
        let pq = B.ColorSpace(primaries: AVVideoColorPrimaries_ITU_R_2020,
                              transfer: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                              matrix: AVVideoYCbCrMatrix_ITU_R_2020)
        #expect(B.outputColorSpace(for: .hevc10, source: pq, target: .bt709) == .rec709)
    }

    @Test func peakAndVariableExpectedRate() {
        var settings = EncodeSettings()
        settings.frameRate = .fps30
        settings.videoOptions.frameRateMode = .peak
        #expect(OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 24)[AVVideoExpectedSourceFrameRateKey] as? Double == 30)
        settings.videoOptions.frameRateMode = .variable
        #expect(OutputSettingsBuilder.compression(settings: settings, sourceFrameRate: 24)[AVVideoExpectedSourceFrameRateKey] as? Double == 24)
    }
}
