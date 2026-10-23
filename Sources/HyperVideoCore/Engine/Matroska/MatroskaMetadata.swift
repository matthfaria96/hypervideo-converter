@preconcurrency import AVFoundation

enum MatroskaMetadata {
    /// What the title, artist, dates and so on of `asset` become in Matroska. The movie
    /// the encoder wrote only has them when the job keeps metadata.
    static func metadata(of asset: AVAsset) async -> MatroskaWriter.Metadata {
        let items = (try? await asset.load(.metadata)) ?? []
        guard !items.isEmpty else { return MatroskaWriter.Metadata() }
        func text(_ identifier: AVMetadataIdentifier) async -> String? {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
                if let date = try? await item.load(.dateValue) { return date.formatted(.iso8601) }
            }
            return nil
        }
        var metadata = MatroskaWriter.Metadata()
        metadata.title = await text(.commonIdentifierTitle)
        var artist = await text(.commonIdentifierArtist)
        if artist == nil { artist = await text(.commonIdentifierCreator) }
        if artist == nil { artist = await text(.commonIdentifierAuthor) }
        let named: [(String, String?)] = [
            ("TITLE", metadata.title),
            ("ARTIST", artist),
            ("ALBUM", await text(.commonIdentifierAlbumName)),
            ("DATE_RELEASED", await text(.commonIdentifierCreationDate)),
            ("DESCRIPTION", await text(.commonIdentifierDescription)),
            ("COPYRIGHT", await text(.commonIdentifierCopyrights)),
            ("PUBLISHER", await text(.commonIdentifierPublisher)),
            ("SUBJECT", await text(.commonIdentifierSubject))
        ]
        metadata.tags = named.compactMap { name, value in value.map { .init(name: name, value: $0) } }
        return metadata
    }
}
