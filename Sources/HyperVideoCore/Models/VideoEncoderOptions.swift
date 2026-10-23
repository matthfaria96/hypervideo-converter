import Foundation

public enum FrameRateMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case constant, peak, variable

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .constant: "Constant Framerate"
        case .peak: "Peak Framerate"
        case .variable: "Variable Framerate"
        }
    }
}

public enum EncoderSpeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case speed, balanced, quality

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .speed: "Speed"
        case .balanced: "Balanced"
        case .quality: "Quality"
        }
    }
}

public enum VideoProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, baseline, main, high, main10

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .baseline: "Baseline"
        case .main: "Main"
        case .high: "High"
        case .main10: "Main 10"
        }
    }

    public static func options(for codec: VideoCodec) -> [VideoProfile] {
        switch codec {
        case .h264: [.auto, .baseline, .main, .high]
        case .hevc: [.auto, .main]
        case .hevc10: [.auto, .main10]
        default: [.auto]
        }
    }

    public func resolved(for codec: VideoCodec) -> VideoProfile {
        Self.options(for: codec).contains(self) ? self : .auto
    }
}

public enum VideoLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case l30 = "3.0", l31 = "3.1", l32 = "3.2"
    case l40 = "4.0", l41 = "4.1", l42 = "4.2"
    case l50 = "5.0", l51 = "5.1", l52 = "5.2"

    public var id: String { rawValue }
    public var displayName: String { self == .auto ? "Auto" : rawValue }

    public static func options(for codec: VideoCodec) -> [VideoLevel] {
        codec == .h264 ? allCases : [.auto]
    }
}

/// Encoder tuning beyond codec and rate control.
public struct VideoEncoderOptions: Codable, Hashable, Sendable {
    public var frameRateMode: FrameRateMode = .constant
    public var speed: EncoderSpeed = .balanced
    public var profile: VideoProfile = .auto
    public var level: VideoLevel = .auto

    public init() {}

    private enum CodingKeys: String, CodingKey { case frameRateMode, speed, profile, level }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VideoEncoderOptions()
        frameRateMode = try c.decodeIfPresent(FrameRateMode.self, forKey: .frameRateMode) ?? d.frameRateMode
        speed = try c.decodeIfPresent(EncoderSpeed.self, forKey: .speed) ?? d.speed
        profile = try c.decodeIfPresent(VideoProfile.self, forKey: .profile) ?? d.profile
        level = try c.decodeIfPresent(VideoLevel.self, forKey: .level) ?? d.level
    }
}
