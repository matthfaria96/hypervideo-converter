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
        let limits = lowRateLimits(sampleRate: sampleRate)
        let ceiling = max(1, min(channelCeiling, sampleRate * 6 * channels / 1_000, limits.max * channels))
        let floor = min(sampleRate >= 44_100 ? (channels >= 8 ? 320 : 32) : limits.min * channels, ceiling)
        return min(max(kbps, floor), ceiling)
    }

    /// Per-channel AAC-LC bitrate range (kbit/s) the system encoder accepts at a sample rate,
    /// found by probing the encoder; rates from 44.1 kHz up keep the generic range.
    private static func lowRateLimits(sampleRate: Int) -> (min: Int, max: Int) {
        switch sampleRate {
        case ..<12_001: (8, 20)
        case ..<16_001: (8, 48)
        case ..<24_001: (16, 48)
        case ..<32_001: (24, 160)
        default: (16, 320)
        }
    }

    static func channelLayoutData(channels: Int) -> Data {
        var layout = AudioChannelLayout()
        switch channels {
        case 1: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case 6: layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_D
        // Apple's AAC encoder rejects MPEG_7_1_C (L R C LFE Ls Rs Rls Rrs) and, with AAC_7_1_B,
        // drops Rls, Rrs and LFE; MPEG_7_1_B is the accepted layout that keeps all eight
        // channels, folding back surrounds into the side pair (pinned by AudioParityTranscodeTests).
        case 8: layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_7_1_B
        default: layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        }
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}
