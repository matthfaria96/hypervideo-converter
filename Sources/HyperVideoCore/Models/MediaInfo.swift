import CoreGraphics
import Foundation

public struct AudioTrackInfo: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var codec: String
    public var channels: Int
    public var sampleRate: Double
    public var language: String?

    public init(id: Int, codec: String, channels: Int, sampleRate: Double, language: String?) {
        self.id = id
        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        self.language = language
    }

    public var channelDescription: String {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels) ch"
        }
    }
}

public enum DynamicRange: String, Codable, Sendable {
    case sdr = "SDR", hdr10 = "HDR10", hlg = "HLG", dolbyVision = "Dolby Vision"
}

public struct MediaInfo: Codable, Hashable, Sendable {
    public var url: URL
    public var duration: Double
    /// Display size after applying the track's orientation.
    public var displaySize: CGSize?
    public var frameRate: Double?
    public var videoCodec: String?
    public var videoBitrate: Double?
    public var dynamicRange: DynamicRange
    public var audioTracks: [AudioTrackInfo]
    public var fileBytes: Int64

    public init(
        url: URL, duration: Double, displaySize: CGSize?, frameRate: Double?, videoCodec: String?,
        videoBitrate: Double?, dynamicRange: DynamicRange, audioTracks: [AudioTrackInfo], fileBytes: Int64
    ) {
        self.url = url
        self.duration = duration
        self.displaySize = displaySize
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.videoBitrate = videoBitrate
        self.dynamicRange = dynamicRange
        self.audioTracks = audioTracks
        self.fileBytes = fileBytes
    }

    public var hasVideo: Bool { displaySize != nil }
    public var isPortrait: Bool { (displaySize?.height ?? 0) > (displaySize?.width ?? 0) }
}

public enum FourCC {
    public static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let text = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
        return friendlyNames[text] ?? text
    }

    private static let friendlyNames: [String: String] = [
        "avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "dvh1": "Dolby Vision",
        "ap4h": "ProRes 4444", "apch": "ProRes 422 HQ", "apcn": "ProRes 422", "apcs": "ProRes 422 LT",
        "apco": "ProRes 422 Proxy", "av01": "AV1", "vp09": "VP9", "mp4v": "MPEG-4",
        "jpeg": "Motion JPEG", "aac": "AAC", "mp4a": "AAC", "alac": "ALAC", "ac-3": "AC-3",
        "ec-3": "E-AC-3", "lpcm": "PCM", ".mp3": "MP3", "opus": "Opus", "fLaC": "FLAC"
    ]
}
