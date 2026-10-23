@preconcurrency import AVFoundation

enum MatroskaMetadata {
    /// What the title, artist, dates and so on of `asset` become in Matroska. The movie the
    /// encoder wrote only has them when the job keeps metadata or sets tags. ACTOR, DIRECTOR,
    /// COMMENT, GENRE and SYNOPSIS come only from the user's `tags`, so default settings write
    /// the same tags as before (D-05) and a music artist isn't relabelled as an actor.
    static func metadata(of asset: AVAsset, tags: MetadataTags = MetadataTags()) async -> MatroskaWriter.Metadata {
        var items = (try? await asset.load(.commonMetadata)) ?? []
        items += (try? await asset.load(.metadata)) ?? []
        let user = userTags(tags)
        guard !items.isEmpty || !user.isEmpty else { return MatroskaWriter.Metadata() }
        var metadata = MatroskaWriter.Metadata()
        metadata.title = await text(items, [.commonIdentifierTitle, .quickTimeMetadataTitle, .iTunesMetadataSongName])
        var artist = await text(items, [.commonIdentifierArtist])
        if artist == nil { artist = await text(items, [.commonIdentifierCreator, .commonIdentifierAuthor]) }
        let named: [(String, String?)] = await [
            ("TITLE", metadata.title),
            ("ARTIST", artist),
            ("ALBUM", text(items, [.commonIdentifierAlbumName])),
            ("DATE_RELEASED", text(items, [.commonIdentifierCreationDate])),
            ("DESCRIPTION", text(items, [.commonIdentifierDescription])),
            ("COPYRIGHT", text(items, [.commonIdentifierCopyrights])),
            ("PUBLISHER", text(items, [.commonIdentifierPublisher])),
            ("SUBJECT", text(items, [.commonIdentifierSubject]))
        ]
        metadata.tags = (named + user).compactMap { name, value in value.map { .init(name: name, value: $0) } }
        return metadata
    }

    /// Tags only the user can set, taken straight from the job's settings.
    static func userTags(_ tags: MetadataTags) -> [(String, String?)] {
        let fields: [(String, String?)] = [
            ("ACTOR", tags.actors), ("DIRECTOR", tags.director), ("COMMENT", tags.comment),
            ("GENRE", tags.genre), ("SYNOPSIS", tags.plot)
        ]
        return fields.compactMap { name, value in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return (name, text)
        }
    }

    /// The first non-empty string (or ISO date) among items with any of `identifiers`.
    private static func text(_ items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
                if let date = try? await item.load(.dateValue) { return date.formatted(.iso8601) }
            }
        }
        return nil
    }
}
