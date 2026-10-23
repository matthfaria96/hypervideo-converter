import Foundation

/// Descriptive tags written to the output; nil means not set.
public struct MetadataTags: Codable, Hashable, Sendable {
    public var title: String?
    public var actors: String?
    public var director: String?
    public var releaseDate: String?
    public var comment: String?
    public var genre: String?
    public var description: String?
    public var plot: String?

    public init(
        title: String? = nil, actors: String? = nil, director: String? = nil, releaseDate: String? = nil,
        comment: String? = nil, genre: String? = nil, description: String? = nil, plot: String? = nil
    ) {
        self.title = title
        self.actors = actors
        self.director = director
        self.releaseDate = releaseDate
        self.comment = comment
        self.genre = genre
        self.description = description
        self.plot = plot
    }

    /// True when every field is nil or only whitespace.
    public var isEmpty: Bool {
        [title, actors, director, releaseDate, comment, genre, description, plot]
            .allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
