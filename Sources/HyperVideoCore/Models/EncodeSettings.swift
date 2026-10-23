import Foundation

public enum ContainerFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4, m4v, mov, mkv

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .m4v: "M4V"
        case .mov: "QuickTime (MOV)"
        case .mkv: "Matroska (MKV)"
        }
    }

    /// Whether the container can hold Apple Lossless audio.
    public var supportsALAC: Bool { self == .mov || self == .mkv }
}

public enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264, hevc, hevc10, proRes422, proRes422HQ, proRes4444, proRes422LT, proRes422Proxy, passthrough

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "H.265 (HEVC)"
        case .hevc10: "H.265 10-bit (HDR)"
        case .proRes422: "Apple ProRes 422"
        case .proRes422HQ: "Apple ProRes 422 HQ"
        case .proRes4444: "Apple ProRes 4444"
        case .proRes422LT: "Apple ProRes 422 LT"
        case .proRes422Proxy: "Apple ProRes 422 Proxy"
        case .passthrough: "Passthrough (no re-encode)"
        }
    }
    public var isProRes: Bool { [.proRes422, .proRes422HQ, .proRes4444, .proRes422LT, .proRes422Proxy].contains(self) }
    public var isTenBit: Bool { self == .hevc10 || isProRes }
    public var supportsRateControl: Bool { self == .h264 || self == .hevc || self == .hevc10 }
}

public enum AudioCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac, heAAC, alac, passthrough, autoPassthru, none

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .aac: "AAC"
        case .heAAC: "HE-AAC"
        case .alac: "Apple Lossless (ALAC)"
        case .passthrough: "Passthrough"
        case .autoPassthru: "Auto Passthru"
        case .none: "No Audio"
        }
    }
}

public enum AudioMixdown: String, Codable, CaseIterable, Identifiable, Sendable {
    case mono, stereo, surround51, surround71

    public var id: String { rawValue }
    public var channelCount: Int {
        switch self {
        case .mono: 1
        case .stereo: 2
        case .surround51: 6
        case .surround71: 8
        }
    }
    public var displayName: String {
        switch self {
        case .mono: "Mono"
        case .stereo: "Stereo"
        case .surround51: "5.1 Surround"
        case .surround71: "7.1 Surround"
        }
    }

    /// Picks the richest layout the source can actually feed.
    public func resolved(sourceChannels: Int) -> AudioMixdown {
        if channelCount <= sourceChannels { return self }
        if self == .surround71 && sourceChannels >= 6 { return .surround51 }
        return sourceChannels >= 2 ? .stereo : .mono
    }
}

public enum AudioTrackSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, first, all
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "None"
        case .first: "First Track"
        case .all: "All Tracks"
        }
    }
}

/// One way of encoding an audio track.
public struct AudioEncoding: Codable, Hashable, Sendable {
    public var codec: AudioCodec
    public var mixdown: AudioMixdown
    public var bitrateKbps: Int
    public var sampleRate: AudioSampleRate = .hz48000
    public var gainDb: Double = 0
    public var trackName: String?
    /// With Auto Passthru, copy only this codec (HandBrake's `copy:<codec>`); nil allows the preset-wide set.
    public var passthruOnly: PassthruCodec?

    public init(
        codec: AudioCodec, mixdown: AudioMixdown, bitrateKbps: Int,
        sampleRate: AudioSampleRate = .hz48000, gainDb: Double = 0, trackName: String? = nil,
        passthruOnly: PassthruCodec? = nil
    ) {
        self.codec = codec
        self.mixdown = mixdown
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.gainDb = gainDb
        self.trackName = trackName
        self.passthruOnly = passthruOnly
    }

    private enum CodingKeys: String, CodingKey {
        case codec, mixdown, bitrateKbps, sampleRate, gainDb, trackName, passthruOnly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codec = try c.decodeIfPresent(AudioCodec.self, forKey: .codec) ?? .aac
        mixdown = try c.decodeIfPresent(AudioMixdown.self, forKey: .mixdown) ?? .stereo
        bitrateKbps = try c.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? 160
        sampleRate = try c.decodeIfPresent(AudioSampleRate.self, forKey: .sampleRate) ?? .hz48000
        gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb) ?? 0
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        passthruOnly = try c.decodeIfPresent(PassthruCodec.self, forKey: .passthruOnly)
    }
}

public enum MaxResolution: Int, Codable, CaseIterable, Identifiable, Sendable {
    case source = 0, uhd4320 = 4320, uhd2160 = 2160, qhd1440 = 1440, fhd1080 = 1080, hd720 = 720, sd576 = 576, sd480 = 480

    public var id: Int { rawValue }
    public var displayName: String { self == .source ? "Source" : "\(rawValue)p" }

    /// Bounding box assuming 16:9; portrait video gets the box transposed.
    public func boundingBox(portrait: Bool) -> CGSize? {
        guard self != .source else { return nil }
        let height = CGFloat(rawValue)
        let width = (height * 16 / 9).rounded()
        return portrait ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

public enum FrameRate: Double, Codable, CaseIterable, Identifiable, Sendable {
    case source = 0
    case fps5 = 5, fps10 = 10, fps12 = 12, fps15 = 15, fps23976 = 23.976, fps24 = 24, fps25 = 25
    case fps2997 = 29.97, fps30 = 30, fps48 = 48, fps50 = 50, fps5994 = 59.94, fps60 = 60
    case fps72 = 72, fps75 = 75, fps90 = 90, fps100 = 100, fps120 = 120

    public var id: Double { rawValue }
    public var displayName: String {
        self == .source ? "Same as Source" : "\(rawValue.formatted(.number.precision(.fractionLength(0...3)))) fps"
    }
}

public enum Rotation: Int, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0, cw90 = 90, cw180 = 180, cw270 = 270
    public var id: Int { rawValue }
    public var displayName: String { self == .none ? "None" : "\(rawValue)°" }
}

public enum RateControl: Codable, Hashable, Sendable {
    /// Constant quality, 0.0 (smallest) ... 1.0 (best).
    case quality(Double)
    /// Average bitrate in kbit/s.
    case averageBitrate(Int)
}

public struct Crop: Codable, Hashable, Sendable {
    public var top: Int
    public var bottom: Int
    public var left: Int
    public var right: Int

    public init(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static let zero = Crop()
    public var isZero: Bool { self == .zero }
}

public struct TrimRange: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double?

    public init(start: Double = 0, end: Double? = nil) {
        self.start = start
        self.end = end
    }
}

public struct EncodeSettings: Codable, Hashable, Sendable {
    public var container: ContainerFormat = .mp4
    public var videoCodec: VideoCodec = .hevc
    public var rateControl: RateControl = .quality(0.62)
    public var frameRate: FrameRate = .source
    public var maxResolution: MaxResolution = .source
    public var crop: Crop = .zero
    public var rotation: Rotation = .none
    public var flipHorizontal = false
    public var allowBFrames = true
    public var keyframeIntervalSeconds: Double = 2
    public var filters = VideoFilters()
    public var videoOptions = VideoEncoderOptions()
    public var pictureOptions = PictureOptions()
    public var alignAVStart = false

    public var audioCodec: AudioCodec = .aac
    public var audioMixdown: AudioMixdown = .stereo
    public var audioBitrateKbps: Int = 160
    public var audioTracks: AudioTrackSelection = .first
    /// A second version of every kept audio track, such as AAC stereo for
    /// compatibility next to a surround passthrough.
    public var extraAudio: AudioEncoding?

    public var audioOptions = AudioOptions()

    public var subtitles: SubtitleSelection = .all
    public var subtitleOptions = SubtitleOptions()
    /// A subtitle drawn into the video for this source; it isn't also kept as a text track.
    public var burnIn: SubtitleBurnIn?

    public var trim: TrimRange?
    public var optimizeForWeb = true
    public var keepMetadata = true
    public var chapterOptions = ChapterOptions()
    public var tags = MetadataTags()

    public init() {}

    /// Legacy "prioritize speed" switch, now the `.speed` stop of the encoder speed.
    public var prioritizeSpeed: Bool {
        get { videoOptions.speed == .speed }
        set {
            if newValue {
                videoOptions.speed = .speed
            } else if videoOptions.speed == .speed {
                videoOptions.speed = .balanced
            }
        }
    }

    /// Problems that would make the encode fail; empty when valid.
    public var validationIssues: [String] {
        var issues: [String] = []
        if videoCodec.isProRes && container != .mov {
            issues.append("Apple ProRes requires the QuickTime (MOV) container.")
        }
        let allEncodings = audioEncodings + audioOptions.tracks.map(\.encoding)
        if allEncodings.contains(where: { $0.codec == .alac }) && !container.supportsALAC {
            issues.append("Apple Lossless audio requires the QuickTime (MOV) or Matroska (MKV) container.")
        }

        if videoCodec == .h264 && maxResolution == .uhd4320 {
            issues.append("H.264 can't encode 8K (4320p); choose H.265 or a lower resolution.")
        }
        if case .averageBitrate(let kbps) = rateControl, kbps < 100 {
            issues.append("Video bitrate must be at least 100 kbit/s.")
        }
        if let trim, let end = trim.end, end <= trim.start {
            issues.append("Trim end must be after trim start.")
        }
        if videoCodec == .passthrough && (!crop.isZero || maxResolution != .source || rotation != .none || flipHorizontal || frameRate != .source) {
            issues.append("Passthrough video can't be cropped, scaled, rotated or retimed.")
        }
        if videoCodec == .passthrough && burnIn != nil {
            issues.append("Burned-in subtitles need the video to be re-encoded, not passed through.")
        }
        // Filters, picture options, crop detection and padding are ignored for passthrough
        // video (nothing is decoded), like an extra
        // audio version while audio is off, so neither can leave a hidden control blocking the encode.
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }

    /// Every encoding applied to each kept audio track, main version first.
    public var audioEncodings: [AudioEncoding] {
        guard audioCodec != .none, audioTracks != .none else { return [] }
        let main = AudioEncoding(
            codec: audioCodec, mixdown: audioMixdown, bitrateKbps: audioBitrateKbps,
            sampleRate: audioOptions.sampleRate, gainDb: audioOptions.gainDb, trackName: audioOptions.trackName,
            passthruOnly: audioOptions.passthruOnly)
        guard let extraAudio, extraAudio.codec != .none else { return [main] }
        return [main, extraAudio]
    }
}
