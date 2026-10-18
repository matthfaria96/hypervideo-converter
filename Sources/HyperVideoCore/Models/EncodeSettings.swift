import Foundation

public enum ContainerFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4, m4v, mov

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .m4v: "M4V"
        case .mov: "QuickTime (MOV)"
        }
    }
}

public enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264, hevc, hevc10, proRes422, proRes422HQ, proRes4444, passthrough

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "H.265 (HEVC)"
        case .hevc10: "H.265 10-bit (HDR)"
        case .proRes422: "Apple ProRes 422"
        case .proRes422HQ: "Apple ProRes 422 HQ"
        case .proRes4444: "Apple ProRes 4444"
        case .passthrough: "Passthrough (no re-encode)"
        }
    }
    public var isProRes: Bool { [.proRes422, .proRes422HQ, .proRes4444].contains(self) }
    public var isTenBit: Bool { self == .hevc10 || isProRes }
    public var supportsRateControl: Bool { self == .h264 || self == .hevc || self == .hevc10 }
}

public enum AudioCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac, alac, passthrough, none

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .aac: "AAC"
        case .alac: "Apple Lossless (ALAC)"
        case .passthrough: "Passthrough"
        case .none: "No Audio"
        }
    }
}

public enum AudioMixdown: String, Codable, CaseIterable, Identifiable, Sendable {
    case mono, stereo, surround51

    public var id: String { rawValue }
    public var channelCount: Int {
        switch self {
        case .mono: 1
        case .stereo: 2
        case .surround51: 6
        }
    }
    public var displayName: String {
        switch self {
        case .mono: "Mono"
        case .stereo: "Stereo"
        case .surround51: "5.1 Surround"
        }
    }

    /// Picks the richest layout the source can actually feed.
    public func resolved(sourceChannels: Int) -> AudioMixdown {
        if channelCount <= sourceChannels { return self }
        return sourceChannels >= 2 ? .stereo : .mono
    }
}

public enum AudioTrackSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case first, all
    public var id: String { rawValue }
    public var displayName: String { self == .first ? "First Track" : "All Tracks" }
}

public enum MaxResolution: Int, Codable, CaseIterable, Identifiable, Sendable {
    case source = 0, uhd2160 = 2160, qhd1440 = 1440, fhd1080 = 1080, hd720 = 720, sd576 = 576, sd480 = 480

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
    case source = 0, fps23976 = 23.976, fps24 = 24, fps25 = 25, fps2997 = 29.97, fps30 = 30, fps50 = 50, fps5994 = 59.94, fps60 = 60

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
    public var prioritizeSpeed = false
    public var allowBFrames = true
    public var keyframeIntervalSeconds: Double = 2

    public var audioCodec: AudioCodec = .aac
    public var audioMixdown: AudioMixdown = .stereo
    public var audioBitrateKbps: Int = 160
    public var audioTracks: AudioTrackSelection = .first

    public var subtitles: SubtitleSelection = .all

    public var trim: TrimRange?
    public var optimizeForWeb = true
    public var keepMetadata = true

    public init() {}

    /// Problems that would make the encode fail; empty when valid.
    public var validationIssues: [String] {
        var issues: [String] = []
        if videoCodec.isProRes && container != .mov {
            issues.append("Apple ProRes requires the QuickTime (MOV) container.")
        }
        if audioCodec == .alac && container != .mov {
            issues.append("Apple Lossless audio requires the QuickTime (MOV) container.")
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
        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }
}

// Decodes every field leniently, so presets and queues saved by older versions
// keep loading after new settings are added.
extension EncodeSettings {
    private enum CodingKeys: String, CodingKey {
        case container, videoCodec, rateControl, frameRate, maxResolution, crop, rotation, flipHorizontal
        case prioritizeSpeed, allowBFrames, keyframeIntervalSeconds
        case audioCodec, audioMixdown, audioBitrateKbps, audioTracks, subtitles
        case trim, optimizeForWeb, keepMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EncodeSettings()
        container = try c.decodeIfPresent(ContainerFormat.self, forKey: .container) ?? d.container
        videoCodec = try c.decodeIfPresent(VideoCodec.self, forKey: .videoCodec) ?? d.videoCodec
        rateControl = try c.decodeIfPresent(RateControl.self, forKey: .rateControl) ?? d.rateControl
        frameRate = try c.decodeIfPresent(FrameRate.self, forKey: .frameRate) ?? d.frameRate
        maxResolution = try c.decodeIfPresent(MaxResolution.self, forKey: .maxResolution) ?? d.maxResolution
        crop = try c.decodeIfPresent(Crop.self, forKey: .crop) ?? d.crop
        rotation = try c.decodeIfPresent(Rotation.self, forKey: .rotation) ?? d.rotation
        flipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? d.flipHorizontal
        prioritizeSpeed = try c.decodeIfPresent(Bool.self, forKey: .prioritizeSpeed) ?? d.prioritizeSpeed
        allowBFrames = try c.decodeIfPresent(Bool.self, forKey: .allowBFrames) ?? d.allowBFrames
        keyframeIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .keyframeIntervalSeconds) ?? d.keyframeIntervalSeconds
        audioCodec = try c.decodeIfPresent(AudioCodec.self, forKey: .audioCodec) ?? d.audioCodec
        audioMixdown = try c.decodeIfPresent(AudioMixdown.self, forKey: .audioMixdown) ?? d.audioMixdown
        audioBitrateKbps = try c.decodeIfPresent(Int.self, forKey: .audioBitrateKbps) ?? d.audioBitrateKbps
        audioTracks = try c.decodeIfPresent(AudioTrackSelection.self, forKey: .audioTracks) ?? d.audioTracks
        subtitles = try c.decodeIfPresent(SubtitleSelection.self, forKey: .subtitles) ?? d.subtitles
        trim = try c.decodeIfPresent(TrimRange.self, forKey: .trim)
        optimizeForWeb = try c.decodeIfPresent(Bool.self, forKey: .optimizeForWeb) ?? d.optimizeForWeb
        keepMetadata = try c.decodeIfPresent(Bool.self, forKey: .keepMetadata) ?? d.keepMetadata
    }
}
