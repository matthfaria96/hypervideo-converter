import Foundation

/// The four quick quality choices of the output inspector. Each is a built-in preset,
/// so jobs made with one name it, and it can be made the default like any preset.
public enum QualityProfile: String, CaseIterable, Identifiable, Sendable {
    case balanced, highQuality, smallerFile, keepOriginal

    public var id: String { rawValue }

    public static let category = "Quality Profiles"

    /// Stable identifiers (60…63) next to the other built-in presets.
    public var presetID: UUID {
        let number = 60 + (Self.allCases.firstIndex(of: self) ?? 0)
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    public var name: String {
        switch self {
        case .balanced: "Balanced"
        case .highQuality: "High Quality"
        case .smallerFile: "Smaller File"
        case .keepOriginal: "Keep Original"
        }
    }

    public var summary: String {
        switch self {
        case .balanced: "Good quality, smaller file"
        case .highQuality: "Preserves detail and sharpness"
        case .smallerFile: "Prioritizes saving space"
        case .keepOriginal: "Doesn't change resolution or frame rate"
        }
    }

    public var symbol: String {
        switch self {
        case .balanced: "sparkle"
        case .highQuality: "diamond"
        case .smallerFile: "arrow.down.circle"
        case .keepOriginal: "arrow.up.right"
        }
    }

    /// The full settings of this profile, starting from the defaults.
    public var settings: EncodeSettings {
        var settings = EncodeSettings()
        settings.container = .mp4
        settings.maxResolution = .source
        settings.frameRate = .source
        switch self {
        case .balanced:
            settings.videoCodec = .h264
            settings.rateControl = .quality(0.62)
        case .highQuality:
            settings.videoCodec = .h264
            settings.rateControl = .quality(0.85)
            settings.audioBitrateKbps = 256
        case .smallerFile:
            settings.videoCodec = .hevc
            settings.rateControl = .quality(0.45)
            settings.maxResolution = .fhd1080
            settings.audioBitrateKbps = 128
        case .keepOriginal:
            settings.videoCodec = .h264
            settings.rateControl = .quality(0.95)
            settings.audioCodec = .passthrough
            settings.audioTracks = .all
        }
        return settings
    }

    /// Settings for Compress mode: the balanced profile in MP4, encoded with HEVC
    /// for about the same quality in a smaller file.
    public static var compressSettings: EncodeSettings { QualityProfile.balanced.settings(compress: true) }

    /// This profile's settings for Compress mode: HEVC instead of H.264, so the same
    /// quality takes less space. "Keep Original" stays as it is.
    public func settings(compress: Bool) -> EncodeSettings {
        var settings = settings
        if compress && self != .keepOriginal { settings.videoCodec = .hevc }
        return settings
    }

    /// Stable identifiers (70…73) of the Compress-mode versions.
    public var compressPresetID: UUID {
        let number = 70 + (Self.allCases.firstIndex(of: self) ?? 0)
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    public func presetID(compress: Bool) -> UUID { compress ? compressPresetID : presetID }

    /// Name of the Compress-mode version, shown on its videos and jobs.
    public var compressName: String {
        switch self {
        case .balanced: "Balanced Compression"
        case .highQuality: "High Quality Compression"
        case .smallerFile: "Maximum Compression"
        case .keepOriginal: "Keep Original"
        }
    }

    /// The Compress-mode versions, as hidden built-in presets.
    public var compressPreset: Preset {
        Preset(id: compressPresetID, name: compressName, category: Self.category, symbol: symbol,
               summary: summary, settings: settings(compress: true), isBuiltIn: true)
    }

    public static var compressPresets: [Preset] { allCases.map(\.compressPreset) }

    public var preset: Preset {
        Preset(id: presetID, name: name, category: Self.category, symbol: symbol,
               summary: summary, settings: settings, isBuiltIn: true)
    }

    public static var presets: [Preset] { allCases.map(\.preset) }

    /// The profile of a preset ID, from either its Convert or its Compress version.
    public static func profile(presetID: UUID?) -> QualityProfile? {
        allCases.first { $0.presetID == presetID || $0.compressPresetID == presetID }
    }

    public static func isCompressPreset(_ id: UUID?) -> Bool { allCases.contains { $0.compressPresetID == id } }
}
