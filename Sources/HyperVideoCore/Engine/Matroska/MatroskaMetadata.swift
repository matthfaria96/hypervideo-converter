@preconcurrency import AVFoundation

enum MatroskaMetadata {
    private static let iTunesPlot = AVMetadataItem.identifier(forKey: "ldes" as NSString, keySpace: .iTunes)

    /// What the title, artist, dates, tags and so on of `asset` become in Matroska. The
    /// movie the encoder wrote only has them when the job keeps metadata or sets tags.
    static func metadata(of asset: AVAsset) async -> MatroskaWriter.Metadata {
        var items = (try? await asset.load(.commonMetadata)) ?? []
        items += (try? await asset.load(.metadata)) ?? []
        guard !items.isEmpty else { return MatroskaWriter.Metadata() }
        var metadata = MatroskaWriter.Metadata()
        metadata.title = await text(items, [.commonIdentifierTitle, .quickTimeMetadataTitle, .iTunesMetadataSongName])
        var artist = await text(items, [.commonIdentifierArtist])
        if artist == nil { artist = await text(items, [.commonIdentifierCreator, .commonIdentifierAuthor]) }
        let named: [(String, String?)] = await [
            ("TITLE", metadata.title),
            ("ARTIST", artist),
            ("ACTOR", text(items, [.quickTimeMetadataArtist, .iTunesMetadataArtist])),
            ("ALBUM", text(items, [.commonIdentifierAlbumName])),
            ("DATE_RELEASED", text(items, [.commonIdentifierCreationDate, .iTunesMetadataReleaseDate])),
            ("DESCRIPTION", text(items, [.commonIdentifierDescription])),
            ("COPYRIGHT", text(items, [.commonIdentifierCopyrights])),
            ("PUBLISHER", text(items, [.commonIdentifierPublisher])),
            ("SUBJECT", text(items, [.commonIdentifierSubject]))
        ]
        let user = await userTags(items)
        metadata.tags = (named + user).compactMap { name, value in value.map { .init(name: name, value: $0) } }
        return metadata
    }

    private static func userTags(_ items: [AVMetadataItem]) async -> [(String, String?)] {
        await [
            ("DIRECTOR", text(items, [.quickTimeMetadataDirector, .iTunesMetadataDirector])),
            ("COMMENT", text(items, [.quickTimeMetadataComment, .iTunesMetadataUserComment])),
            ("GENRE", text(items, [.quickTimeMetadataGenre, .iTunesMetadataUserGenre])),
            ("SYNOPSIS", text(items, [.quickTimeMetadataInformation] + (iTunesPlot.map { [$0] } ?? [])))
        ]
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
