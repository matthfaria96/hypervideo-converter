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
        }
    }

    public static func readerPixelFormat(for codec: VideoCodec) -> OSType {
        codec.isTenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    /// HDR survives only on a 10-bit path; everything else is tone-tagged as Rec. 709.
    public static func outputColorSpace(for codec: VideoCodec, source: ColorSpace?) -> ColorSpace {
        guard let source, codec.isTenBit else { return .rec709 }
        return source
    }

    public static func video(
        settings: EncodeSettings,
        renderSize: CGSize,
        sourceFrameRate: Double?,
        color: ColorSpace
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
        if settings.videoCodec.supportsRateControl {
            output[AVVideoCompressionPropertiesKey] = compression(settings: settings, sourceFrameRate: sourceFrameRate)
        }
        return output
    }

    static func compression(settings: EncodeSettings, sourceFrameRate: Double?) -> [String: Any] {
        let fps = settings.frameRate == .source ? (sourceFrameRate ?? 30) : settings.frameRate.rawValue
        var props: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalDurationKey: settings.keyframeIntervalSeconds,
            AVVideoAllowFrameReorderingKey: settings.allowBFrames,
            AVVideoProfileLevelKey: profile(settings.videoCodec)
        ]
        switch settings.rateControl {
        case .quality(let value):
            props[AVVideoQualityKey] = min(max(value, 0), 1)
        case .averageBitrate(let kbps):
            props[AVVideoAverageBitRateKey] = kbps * 1_000
        }
        if settings.prioritizeSpeed {
            props[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
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
        }
    }

    static func profile(_ codec: VideoCodec) -> String {
        switch codec {
        case .h264: AVVideoProfileLevelH264HighAutoLevel
        case .hevc10: kVTProfileLevel_HEVC_Main10_AutoLevel as String
        default: kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
    }

    public static func audioReaderPCM(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: channelLayoutData(channels: channels)
        ]
    }

    public static func audioWriter(encoding: AudioEncoding, channels: Int) -> [String: Any] {
        var output: [String: Any] = [
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: channelLayoutData(channels: channels)
        ]
        switch encoding.codec {
        case .alac:
            output[AVFormatIDKey] = kAudioFormatAppleLossless
            output[AVEncoderBitDepthHintKey] = 24
        default:
            output[AVFormatIDKey] = kAudioFormatMPEG4AAC
            output[AVEncoderBitRateKey] = clampedAACBitrate(encoding.bitrateKbps, channels: channels) * 1_000
        }
        return output
    }

    /// AAC encoder rejects bitrates outside roughly 32–320 kbit/s per stereo pair.
    static func clampedAACBitrate(_ kbps: Int, channels: Int) -> Int {
        let ceiling = channels >= 6 ? 640 : (channels == 1 ? 256 : 320)
        return min(max(kbps, 32), ceiling)
    }

    static func channelLayoutData(channels: Int) -> Data {
        var layout = AudioChannelLayout()
        switch channels {
        case 1: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case 6: layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_D
        default: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        }
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}
