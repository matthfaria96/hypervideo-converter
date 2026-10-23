import AVFoundation
import CoreMedia

extension OutputSettingsBuilder {
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
