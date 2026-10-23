import Foundation

public enum SubtitleSelection: String, Codable, CaseIterable, Identifiable, Sendable {
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

/// A text subtitle or closed-caption track found in the source.
public struct SubtitleTrackInfo: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case subtitle, closedCaption

        /// AVAssetWriter only accepts closed-caption tracks in QuickTime movies.
        public func isSupported(in container: ContainerFormat) -> Bool {
            self == .subtitle || container == .mov
        }
    }

    public var id: Int
    public var kind: Kind
    /// Friendly format name, e.g. "Timed Text".
    public var format: String
    public var language: String?
    /// The track's own title, when the source has one.
    public var name: String?
    /// Whether the track holds only forced lines; nil when unknown.
    public var forcedOnly: Bool?

    public init(id: Int, kind: Kind, format: String, language: String?, name: String? = nil, forcedOnly: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.format = format
        self.language = language
        self.name = name
        self.forcedOnly = forcedOnly
    }

    public var isForcedOnly: Bool { forcedOnly ?? false }

    /// The tracks an encode keeps: those the container can hold, narrowed by `selection`.
    public static func kept<Track>(
        _ tracks: [Track], kind: (Track) -> Kind, selection: SubtitleSelection, container: ContainerFormat
    ) -> [Track] {
        let supported = tracks.filter { kind($0).isSupported(in: container) }
        switch selection {
        case .none: return []
        case .first: return Array(supported.prefix(1))
        case .all: return supported
        }
    }
}

/// One subtitle drawn into the picture instead of being kept as a text track.
public enum SubtitleBurnIn: Codable, Hashable, Sendable {
    /// A source text track, by track ID.
    case track(id: Int)
    /// An external SRT/WebVTT file added to the source.
    case file(URL)
}
