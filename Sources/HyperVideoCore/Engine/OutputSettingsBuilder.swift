import AVFoundation
import CoreMedia
import VideoToolbox

/// Pure translation of `EncodeSettings` into AVFoundation dictionaries.
public enum OutputSettingsBuilder {
    public struct ColorSpace: Equatable, Sendable {
        public var primaries: String
        public var transfer: String
        public var matrix: String

        public static let rec709 = ColorSpace(
            primaries: AVVideoColorPrimaries_ITU_R_709_2,
            transfer: AVVideoTransferFunction_ITU_R_709_2,
            matrix: AVVideoYCbCrMatrix_ITU_R_709_2
        )

        public static let bt601NTSC = ColorSpace(
            primaries: AVVideoColorPrimaries_SMPTE_C,
            transfer: AVVideoTransferFunction_ITU_R_709_2,
            matrix: AVVideoYCbCrMatrix_ITU_R_601_4
        )
        public static let bt601PAL = ColorSpace(
            primaries: AVVideoColorPrimaries_EBU_3213,
            transfer: AVVideoTransferFunction_ITU_R_709_2,
            matrix: AVVideoYCbCrMatrix_ITU_R_601_4
        )
        public static let bt2020 = ColorSpace(
            primaries: AVVideoColorPrimaries_ITU_R_2020,
            transfer: AVVideoTransferFunction_ITU_R_709_2,
            matrix: AVVideoYCbCrMatrix_ITU_R_2020
        )

        public var isHDR: Bool {
            transfer == AVVideoTransferFunction_SMPTE_ST_2084_PQ || transfer == AVVideoTransferFunction_ITU_R_2100_HLG
        }
    }

    /// The file AVAssetWriter writes. MKV is encoded into a QuickTime movie first
    /// and then remuxed by `MatroskaRemuxer`, since AVFoundation can't write Matroska.
    public static func fileType(for container: ContainerFormat) -> AVFileType {
        switch container {
        case .mp4: .mp4
        case .m4v: .m4v
        case .mov, .mkv: .mov
        case .m4a: .m4a
        }
    }

    public static func readerPixelFormat(for codec: VideoCodec) -> OSType {
        codec.isTenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    /// HDR survives only on a 10-bit path; everything else is tone-tagged as Rec. 709.
    /// A chosen colorspace target overrides the source's own tags.
    public static func outputColorSpace(
        for codec: VideoCodec, source: ColorSpace?, target: ColorspaceTarget = .off
    ) -> ColorSpace {
        switch target {
        case .bt709: return .rec709
        case .bt601ntsc: return .bt601NTSC
        case .bt601pal: return .bt601PAL
        case .bt2020: return .bt2020
        case .off:
            guard let source, codec.isTenBit else { return .rec709 }
            return source
        }
    }

    public static func video(
        settings: EncodeSettings,
        renderSize: CGSize,
        sourceFrameRate: Double?,
        color: ColorSpace,
        pixelAspect: CGSize? = nil
    ) -> [String: Any] {
        var output: [String: Any] = [
            AVVideoCodecKey: codecType(settings.videoCodec),
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: color.primaries,
                AVVideoTransferFunctionKey: color.transfer,
                AVVideoYCbCrMatrixKey: color.matrix
            ]
        ]
        if let pixelAspect, pixelAspect.width > 0, pixelAspect.height > 0, pixelAspect.width != pixelAspect.height {
            output[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: Int(pixelAspect.width),
                AVVideoPixelAspectRatioVerticalSpacingKey: Int(pixelAspect.height)
            ]
        }
        if settings.videoCodec.supportsRateControl {
            output[AVVideoCompressionPropertiesKey] = compression(settings: settings, sourceFrameRate: sourceFrameRate)
        }
        return output
    }

    static func compression(settings: EncodeSettings, sourceFrameRate: Double?) -> [String: Any] {
        let followsSource = settings.frameRate == .source || settings.videoOptions.frameRateMode == .variable
        let fps = followsSource ? (sourceFrameRate ?? 30) : settings.frameRate.rawValue
        var props: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalDurationKey: settings.keyframeIntervalSeconds,
            // H.264 Baseline has no B-frames, so don't leave it to VideoToolbox to ignore the request.
            AVVideoAllowFrameReorderingKey: settings.allowBFrames
                && !(settings.videoCodec == .h264 && settings.videoOptions.profile == .baseline),
            AVVideoProfileLevelKey: profileLevel(
                codec: settings.videoCodec, profile: settings.videoOptions.profile, level: settings.videoOptions.level
            )
        ]
        switch settings.rateControl {
        case .quality(let value):
            props[AVVideoQualityKey] = min(max(value, 0), 1)
        case .averageBitrate(let kbps):
            props[AVVideoAverageBitRateKey] = kbps * 1_000
        }
        switch settings.videoOptions.speed {
        case .speed:
            props[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
        case .quality:
            props[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = false
            props[kVTCompressionPropertyKey_MaximizePowerEfficiency as String] = false
        case .balanced:
            break
        }
        return props
    }

    static func codecType(_ codec: VideoCodec) -> AVVideoCodecType {
        switch codec {
        case .h264: .h264
        case .hevc, .hevc10, .passthrough: .hevc
        case .proRes422: .proRes422
        case .proRes422HQ: .proRes422HQ
        case .proRes4444: .proRes4444
        case .proRes422LT: .proRes422LT
        case .proRes422Proxy: .proRes422Proxy
        }
    }

    /// H.264 honours profile and level (VideoToolbox names `H264_<Profile>_<L_M>`); HEVC only has AutoLevel.
    static func profileLevel(codec: VideoCodec, profile: VideoProfile, level: VideoLevel) -> String {
        guard codec == .h264 else {
            return codec == .hevc10 ? kVTProfileLevel_HEVC_Main10_AutoLevel as String : kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
        let resolved = profile.resolved(for: codec)
        if level == .auto {
            switch resolved {
            case .baseline: return AVVideoProfileLevelH264BaselineAutoLevel
            case .main: return AVVideoProfileLevelH264MainAutoLevel
            default: return AVVideoProfileLevelH264HighAutoLevel
            }
        }
        let name = resolved == .baseline ? "Baseline" : resolved == .main ? "Main" : "High"
        return "H264_\(name)_\(level.rawValue.replacingOccurrences(of: ".", with: "_"))"
    }
}
