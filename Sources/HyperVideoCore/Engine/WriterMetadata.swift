@preconcurrency import AVFoundation

/// The metadata items the output movie carries at the movie level.
enum WriterMetadata {
    private struct Row {
        let keyPath: KeyPath<MetadataTags, String?>
        let iTunes: AVMetadataIdentifier
        let quickTime: AVMetadataIdentifier
        let commonKey: AVMetadataKey?
    }

    private static let plotIdentifier = AVMetadataItem.identifier(
        forKey: "ldes" as NSString, keySpace: .iTunes) ?? .iTunesMetadataDescription

    private static let rows: [Row] = [
        Row(keyPath: \.title, iTunes: .iTunesMetadataSongName, quickTime: .quickTimeMetadataTitle, commonKey: .commonKeyTitle),
        Row(keyPath: \.actors, iTunes: .iTunesMetadataArtist, quickTime: .quickTimeMetadataArtist, commonKey: .commonKeyArtist),
        Row(keyPath: \.director, iTunes: .iTunesMetadataDirector, quickTime: .quickTimeMetadataDirector, commonKey: nil),
        Row(keyPath: \.releaseDate, iTunes: .iTunesMetadataReleaseDate, quickTime: .quickTimeMetadataCreationDate,
            commonKey: .commonKeyCreationDate),
        Row(keyPath: \.comment, iTunes: .iTunesMetadataUserComment, quickTime: .quickTimeMetadataComment, commonKey: nil),
        Row(keyPath: \.genre, iTunes: .iTunesMetadataUserGenre, quickTime: .quickTimeMetadataGenre, commonKey: nil),
        Row(keyPath: \.description, iTunes: .iTunesMetadataDescription, quickTime: .quickTimeMetadataDescription,
            commonKey: .commonKeyDescription),
        Row(keyPath: \.plot, iTunes: plotIdentifier, quickTime: .quickTimeMetadataInformation, commonKey: nil)
    ]

    static func items(source: AVAsset, settings: EncodeSettings) async -> [AVMetadataItem] {
        let base = settings.keepMetadata ? ((try? await source.load(.metadata)) ?? []) : []
        return merged(base: base, tags: settings.tags, container: settings.container)
    }

    private static func usesITunes(_ container: ContainerFormat) -> Bool { container == .mp4 || container == .m4v }

    private static func value(_ row: Row, _ tags: MetadataTags) -> String? {
        guard let text = tags[keyPath: row.keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func tagItems(_ tags: MetadataTags, container: ContainerFormat) -> [AVMetadataItem] {
        rows.compactMap { row in
            guard let text = value(row, tags) else { return nil }
            let item = AVMutableMetadataItem()
            item.identifier = usesITunes(container) ? row.iTunes : row.quickTime
            item.value = text as NSString
            item.extendedLanguageTag = "und"
            return item.copy() as? AVMetadataItem
        }
    }

    static func merged(base: [AVMetadataItem], tags: MetadataTags, container: ContainerFormat) -> [AVMetadataItem] {
        let overridden = rows.filter { value($0, tags) != nil }
        guard !overridden.isEmpty else { return base }
        let identifiers = Set(overridden.flatMap { [$0.iTunes, $0.quickTime] })
        let commonKeys = Set(overridden.compactMap(\.commonKey))
        let kept = base.filter { item in
            if let identifier = item.identifier, identifiers.contains(identifier) { return false }
            if let key = item.commonKey, commonKeys.contains(key) { return false }
            return true
        }
        return kept + tagItems(tags, container: container)
    }
}
