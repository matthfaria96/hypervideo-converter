import Foundation

/// How one source subtitle track is written to the output.
public struct SubtitleTrackSetting: Codable, Hashable, Identifiable, Sendable {
    public var sourceTrackID: Int
    public var include = true
    public var isDefault = false
    public var forcedOnly = false
    public var name: String?

    public var id: Int { sourceTrackID }

    public init(
        sourceTrackID: Int, include: Bool = true, isDefault: Bool = false,
        forcedOnly: Bool = false, name: String? = nil
    ) {
        self.sourceTrackID = sourceTrackID
        self.include = include
        self.isDefault = isDefault
        self.forcedOnly = forcedOnly
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case sourceTrackID, include, isDefault, forcedOnly, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceTrackID = try c.decode(Int.self, forKey: .sourceTrackID)
        include = try c.decodeIfPresent(Bool.self, forKey: .include) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        forcedOnly = try c.decodeIfPresent(Bool.self, forKey: .forcedOnly) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

public struct SubtitleOptions: Codable, Hashable, Sendable {
    /// ISO 639 language filter; empty keeps every language.
    public var languages: [String] = []
    /// Empty means "use the selection behaviour".
    public var tracks: [SubtitleTrackSetting] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case languages, tracks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        tracks = try c.decodeIfPresent([SubtitleTrackSetting].self, forKey: .tracks) ?? []
    }
}
