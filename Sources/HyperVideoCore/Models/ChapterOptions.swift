import Foundation

public struct ChapterOptions: Codable, Hashable, Sendable {
    /// nil follows `keepMetadata`, which is today's behaviour.
    public var markers: Bool?
    /// Per source chapter index; an empty string keeps the source title.
    public var titles: [String] = []

    public init() {}

    public func writesMarkers(keepMetadata: Bool) -> Bool { markers ?? keepMetadata }

    private enum CodingKeys: String, CodingKey { case markers, titles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markers = try c.decodeIfPresent(Bool.self, forKey: .markers)
        titles = try c.decodeIfPresent([String].self, forKey: .titles) ?? []
    }
}
