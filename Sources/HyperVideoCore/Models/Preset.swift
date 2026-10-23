import Foundation

public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String
    public var symbol: String
    public var summary: String
    public var settings: EncodeSettings
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        category: String,
        symbol: String,
        summary: String,
        settings: EncodeSettings,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.symbol = symbol
        self.summary = summary
        self.settings = settings
        self.isBuiltIn = isBuiltIn
    }
}

public enum BuiltInPresets {
    /// Stable identifiers so selections survive relaunches.
    private static func id(_ n: Int) -> UUID { stableID(n) }

    /// `00000000-0000-0000-0000-` followed by `n` as twelve decimal digits, built from bytes
    /// so no string parsing (and no force unwrap) is involved.
    static func stableID(_ n: Int) -> UUID {
        let text = String(max(0, min(n, 999_999_999_999)))
        let digits = (String(repeating: "0", count: 12 - text.count) + text).compactMap(\.wholeNumberValue)
        let tail = (0..<6).map { UInt8(digits[2 * $0] << 4 | digits[2 * $0 + 1]) }
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tail[0], tail[1], tail[2], tail[3], tail[4], tail[5]))
    }

    private static func make(
        _ n: Int, _ name: String, _ category: String, _ symbol: String, _ summary: String,
        _ configure: (inout EncodeSettings) -> Void
    ) -> Preset {
        var settings = EncodeSettings()
        configure(&settings)
        return Preset(id: id(n), name: name, category: category, symbol: symbol,
                      summary: summary, settings: settings, isBuiltIn: true)
    }

    public static let all: [Preset] = [
        make(1, "Fast 1080p30", "General", "hare", "H.264 · 1080p · 30 fps · AAC stereo") {
            $0.videoCodec = .h264; $0.maxResolution = .fhd1080; $0.frameRate = .fps30
            $0.rateControl = .quality(0.55); $0.prioritizeSpeed = true
        },
        make(2, "HQ 1080p30 Surround", "General", "sparkles", "HEVC · 1080p · 30 fps · AAC 5.1") {
            $0.videoCodec = .hevc; $0.maxResolution = .fhd1080; $0.frameRate = .fps30
            $0.rateControl = .quality(0.7); $0.audioMixdown = .surround51; $0.audioBitrateKbps = 384
        },
        make(3, "Fast 720p30", "General", "hare", "H.264 · 720p · 30 fps · AAC stereo") {
            $0.videoCodec = .h264; $0.maxResolution = .hd720; $0.frameRate = .fps30
            $0.rateControl = .quality(0.52); $0.prioritizeSpeed = true
        },
        make(4, "Fast 480p30", "General", "hare", "H.264 · 480p · 30 fps · AAC stereo") {
            $0.videoCodec = .h264; $0.maxResolution = .sd480; $0.frameRate = .fps30
            $0.rateControl = .quality(0.5); $0.prioritizeSpeed = true; $0.audioBitrateKbps = 128
        },
        make(10, "4K HEVC 60 HDR", "4K & HDR", "4k.tv", "HEVC 10-bit · 2160p · 60 fps · HDR preserved") {
            $0.videoCodec = .hevc10; $0.maxResolution = .uhd2160; $0.frameRate = .fps60
            $0.rateControl = .quality(0.72); $0.audioMixdown = .surround51; $0.audioBitrateKbps = 384
            $0.container = .mov
        },
        make(11, "4K HEVC 30", "4K & HDR", "4k.tv", "HEVC · 2160p · 30 fps") {
            $0.videoCodec = .hevc; $0.maxResolution = .uhd2160; $0.frameRate = .fps30
            $0.rateControl = .quality(0.68)
        },
        make(20, "Apple 1080p60 Surround", "Devices", "appletv", "Apple TV, iPhone, iPad, Mac") {
            $0.videoCodec = .hevc; $0.maxResolution = .fhd1080; $0.frameRate = .fps60
            $0.container = .m4v; $0.audioMixdown = .surround51; $0.audioBitrateKbps = 384
        },
        make(21, "Apple 720p30", "Devices", "iphone", "Compact for older Apple devices") {
            $0.videoCodec = .h264; $0.maxResolution = .hd720; $0.frameRate = .fps30
            $0.container = .m4v
        },
        make(30, "Discord Small", "Web", "bubble.left.and.bubble.right", "≈ 2.5 Mbit/s H.264 720p, fits upload limits") {
            $0.videoCodec = .h264; $0.maxResolution = .hd720; $0.frameRate = .fps30
            $0.rateControl = .averageBitrate(2_500); $0.audioBitrateKbps = 96
        },
        make(31, "YouTube 1080p60", "Web", "play.rectangle", "High-bitrate H.264 for upload") {
            $0.videoCodec = .h264; $0.maxResolution = .fhd1080; $0.frameRate = .fps60
            $0.rateControl = .averageBitrate(12_000); $0.audioBitrateKbps = 320
        },
        make(32, "Social Vertical 1080p", "Web", "rectangle.portrait", "Reels / TikTok / Shorts") {
            $0.videoCodec = .h264; $0.maxResolution = .fhd1080; $0.frameRate = .fps30
            $0.rateControl = .averageBitrate(8_000)
        },
        make(40, "ProRes 422 Production", "Production", "film", "Edit-friendly intermediate, source size") {
            $0.videoCodec = .proRes422; $0.container = .mov; $0.audioCodec = .alac
        },
        make(41, "ProRes 422 HQ Production", "Production", "film.stack", "Highest-quality 4:2:2 intermediate") {
            $0.videoCodec = .proRes422HQ; $0.container = .mov; $0.audioCodec = .alac
        },
        make(50, "Remux (Passthrough)", "Production", "arrow.triangle.2.circlepath", "Copy streams without re-encoding") {
            $0.videoCodec = .passthrough; $0.audioCodec = .passthrough; $0.audioTracks = .all
            $0.container = .mov; $0.optimizeForWeb = false
        }
    ]

    public static var `default`: Preset { all[1] }
}
