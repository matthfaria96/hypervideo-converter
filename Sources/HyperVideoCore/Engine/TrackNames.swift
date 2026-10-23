@preconcurrency import AVFoundation

/// Reads and writes the user-visible name of a track (the QuickTime track-name atom).
enum TrackNames {
    static func items(_ name: String) -> [AVMetadataItem] {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeUserDataTrackName
        item.value = name as NSString
        item.extendedLanguageTag = "und"
        return [item.copy() as? AVMetadataItem].compactMap { $0 }
    }

    static func name(of track: AVAssetTrack) async -> String? {
        guard let metadata = try? await track.load(.metadata) else { return nil }
        let identifiers: [AVMetadataIdentifier] = [.quickTimeUserDataTrackName, .quickTimeMetadataTitle, .commonIdentifierTitle]
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            }
        }
        return nil
    }
}
