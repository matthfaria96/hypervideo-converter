import CoreAudioTypes
import Foundation

public enum AudioSampleRate: Int, Codable, CaseIterable, Identifiable, Sendable {
    case auto = 0
    case hz8000 = 8000, hz11025 = 11025, hz12000 = 12000, hz16000 = 16000
    case hz22050 = 22050, hz24000 = 24000, hz32000 = 32000, hz44100 = 44100, hz48000 = 48000

    public var id: Int { rawValue }
    public var displayName: String {
        guard self != .auto else { return "Auto" }
        // Built by hand so the label doesn't change with the system's decimal separator.
        let whole = rawValue / 1000
        let fraction = String(format: "%03d", rawValue % 1000).replacing(/0+$/, with: "")
        return fraction.isEmpty ? "\(whole) kHz" : "\(whole).\(fraction) kHz"
    }

    private static let fixedRates = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000]

    /// The sample rate to encode at for a source and codec.
    public func resolved(sourceRate: Double, codec: AudioCodec) -> Int {
        let base: Int
        if self == .auto {
            if codec == .alac {
                base = Int(min(max(sourceRate, 8000), 192_000))
            } else {
                base = Self.fixedRates.last { Double($0) <= sourceRate } ?? 8000
            }
        } else {
            base = rawValue
        }
        return codec == .heAAC ? max(base, 32_000) : base
    }
}

public enum PassthruCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case aac, ac3, eac3, dts, dtshd, truehd, mp3, mp2, flac, opus, alac, vorbis

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .aac: "AAC"
        case .ac3: "AC3"
        case .eac3: "E-AC3"
        case .dts: "DTS"
        case .dtshd: "DTS-HD"
        case .truehd: "TrueHD"
        case .mp3: "MP3"
        case .mp2: "MP2"
        case .flac: "FLAC"
        case .opus: "Opus"
        case .alac: "ALAC"
        case .vorbis: "Vorbis"
        }
    }

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// The passthrough family of a Core Audio format ID, nil for uncompressed or unknown audio.
    public static func from(formatID: UInt32) -> PassthruCodec? {
        switch formatID {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD: return .aac
        case kAudioFormatAC3: return .ac3
        case kAudioFormatEnhancedAC3: return .eac3
        case kAudioFormatMPEGLayer3: return .mp3
        case kAudioFormatMPEGLayer2: return .mp2
        case kAudioFormatFLAC: return .flac
        case kAudioFormatOpus: return .opus
        case kAudioFormatAppleLossless: return .alac
        case fourCC("dtsc"), fourCC("dtse"): return .dts
        case fourCC("dtsh"), fourCC("dtsl"): return .dtshd
        case fourCC("mlpa"): return .truehd
        case fourCC("vorb"): return .vorbis
        default: return nil
        }
    }
}

/// One source audio track with its own output encoding.
public struct AudioTrackSetting: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var sourceTrackID: Int
    public var encoding: AudioEncoding

    public init(id: UUID = UUID(), sourceTrackID: Int, encoding: AudioEncoding) {
        self.id = id
        self.sourceTrackID = sourceTrackID
        self.encoding = encoding
    }
}

public struct AudioOptions: Codable, Hashable, Sendable {
    /// ISO 639 language filter; empty keeps every language.
    public var languages: [String] = []
    public var allowedPassthru: Set<PassthruCodec> = Set(PassthruCodec.allCases)
    public var fallback: AudioCodec = .aac
    public var extraFirstTrackOnly = false
    /// Sample rate of the main version; 48 kHz is today's behaviour.
    public var sampleRate: AudioSampleRate = .hz48000
    public var gainDb: Double = 0
    /// Name of the main version.
    public var trackName: String?
    public var automaticNaming = false
    /// Empty means "use the selection behaviour".
    public var tracks: [AudioTrackSetting] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case languages, allowedPassthru, fallback, extraFirstTrackOnly, sampleRate
        case gainDb, trackName, automaticNaming, tracks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AudioOptions()
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? d.languages
        allowedPassthru = try c.decodeIfPresent(Set<PassthruCodec>.self, forKey: .allowedPassthru) ?? d.allowedPassthru
        fallback = try c.decodeIfPresent(AudioCodec.self, forKey: .fallback) ?? d.fallback
        extraFirstTrackOnly = try c.decodeIfPresent(Bool.self, forKey: .extraFirstTrackOnly) ?? d.extraFirstTrackOnly
        sampleRate = try c.decodeIfPresent(AudioSampleRate.self, forKey: .sampleRate) ?? d.sampleRate
        gainDb = try c.decodeIfPresent(Double.self, forKey: .gainDb) ?? d.gainDb
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        automaticNaming = try c.decodeIfPresent(Bool.self, forKey: .automaticNaming) ?? d.automaticNaming
        tracks = try c.decodeIfPresent([AudioTrackSetting].self, forKey: .tracks) ?? d.tracks
    }
}
