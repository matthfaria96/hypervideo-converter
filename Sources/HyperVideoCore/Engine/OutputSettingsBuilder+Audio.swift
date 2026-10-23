import AVFoundation
import CoreMedia

extension OutputSettingsBuilder {
    public static func audioReaderPCM(channels: Int, sampleRate: Int = 48_000) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: channelLayoutData(channels: channels)
        ]
    }

    public static func audioWriter(encoding: AudioEncoding, channels: Int, sampleRate: Int = 48_000) -> [String: Any] {
        var output: [String: Any] = [
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: channelLayoutData(channels: channels)
        ]
        switch encoding.codec {
        case .alac:
            output[AVFormatIDKey] = kAudioFormatAppleLossless
            output[AVEncoderBitDepthHintKey] = 24
        case .heAAC:
            output[AVFormatIDKey] = kAudioFormatMPEG4AAC_HE
            output[AVEncoderBitRateKey] = clampedAACBitrate(
                encoding.bitrateKbps, channels: channels, sampleRate: sampleRate, highEfficiency: true) * 1_000
        default:
            output[AVFormatIDKey] = kAudioFormatMPEG4AAC
            output[AVEncoderBitRateKey] = clampedAACBitrate(
                encoding.bitrateKbps, channels: channels, sampleRate: sampleRate) * 1_000
        }
        return output
    }

    /// The AAC encoder rejects bitrates outside a range that depends on channels and sample rate.
    static func clampedAACBitrate(
        _ kbps: Int, channels: Int, sampleRate: Int = 48_000, highEfficiency: Bool = false
    ) -> Int {
        if highEfficiency {
            let ceiling = channels == 1 ? 64 : (channels <= 2 ? 80 : 320)
            return min(max(kbps, 16), ceiling)
        }
        let channelCeiling = channels >= 6 ? 640 : (channels == 1 ? 256 : 320)
        let ceiling = max(1, min(channelCeiling, sampleRate * 6 * channels / 1_000))
        return min(max(kbps, min(32, ceiling)), ceiling)
    }

    static func channelLayoutData(channels: Int) -> Data {
        var layout = AudioChannelLayout()
        switch channels {
        case 1: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case 6: layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_D
        case 8: layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_7_1_C
        default: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        }
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}
