import CoreGraphics
import Foundation

/// A size shown before encoding, with how much it can be trusted.
public struct SizePrediction: Equatable, Sendable {
    public enum Kind: Int, Comparable, Sendable {
        /// Passthrough: the streams are copied, so the size is known.
        case exact
        /// Average bitrate: the encoder aims at it and usually lands at or below.
        case upTo
        /// Constant quality: a rule of thumb, the content decides.
        case approximate

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var bytes: Int64
    public var kind: Kind

    public init(bytes: Int64, kind: Kind) {
        self.bytes = bytes
        self.kind = kind
    }
}

public extension OutputEstimate {
    /// A size for any settings: exact or bitrate-based where possible, otherwise a
    /// bits-per-pixel rule of thumb × output resolution × frame rate × duration, plus audio.
    static func prediction(info: MediaInfo, settings: EncodeSettings) -> SizePrediction? {
        if let bytes = bytes(info: info, settings: settings) {
            return SizePrediction(bytes: bytes, kind: settings.videoCodec == .passthrough ? .exact : .upTo)
        }
        let duration = settings.outputDuration(sourceDuration: info.duration)
        guard duration > 0 else { return nil }
        let audio = audioBitsPerSecond(info: info, settings: settings) ?? fallbackAudioBitsPerSecond(info: info, settings: settings)
        let bits = (videoBitsPerSecond(info: info, settings: settings) + audio) * duration
        return SizePrediction(bytes: Int64((bits / 8).rounded()), kind: .approximate)
    }

    /// Rule-of-thumb bits per pixel per frame. Constant quality 0…1 grows the rate
    /// quadratically; HEVC needs about 40% less than H.264 for the same look.
    static func bitsPerPixel(codec: VideoCodec, quality: Double) -> Double {
        let h264 = 0.02 + 0.2 * quality * quality
        switch codec {
        case .h264: return h264
        case .hevc: return h264 * 0.6
        case .hevc10: return h264 * 0.65
        case .proRes422: return 2.4
        case .proRes422HQ: return 3.6
        case .proRes4444: return 5.4
        case .proRes422LT: return 1.7
        case .proRes422Proxy: return 0.75
        case .passthrough: return 0
        }
    }

    /// Output picture size: the source fitted into the maximum resolution, never enlarged.
    static func outputPixels(info: MediaInfo, settings: EncodeSettings) -> Double {
        guard let size = info.displaySize, size.width > 0, size.height > 0 else { return 0 }
        guard let box = settings.maxResolution.boundingBox(portrait: size.height > size.width) else {
            return Double(size.width * size.height)
        }
        let scale = min(1, box.width / size.width, box.height / size.height)
        return Double(size.width * scale * size.height * scale)
    }

    private static func videoBitsPerSecond(info: MediaInfo, settings: EncodeSettings) -> Double {
        let quality: Double
        if case .quality(let value) = settings.rateControl { quality = value } else { quality = 0.62 }
        let fps = settings.outputFrameRate(sourceFrameRate: info.frameRate) ?? 30
        let rate = bitsPerPixel(codec: settings.videoCodec, quality: quality) * outputPixels(info: info, settings: settings) * fps
        // Re-encoding with a quality target rarely ends up above the source's own rate.
        guard !settings.videoCodec.isProRes, let source = info.videoBitrate, source > 0 else { return rate }
        return min(rate, source)
    }

    /// When a passthrough track doesn't report its rate: 160 kbit/s per kept track.
    private static func fallbackAudioBitsPerSecond(info: MediaInfo, settings: EncodeSettings) -> Double {
        let tracks: Int
        switch settings.audioTracks {
        case .none: tracks = 0
        case .first: tracks = min(info.audioTracks.count, 1)
        case .all: tracks = info.audioTracks.count
        }
        return Double(settings.audioEncodings.count * tracks) * 160_000
    }
}
