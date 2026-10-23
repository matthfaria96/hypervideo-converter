@preconcurrency import AVFoundation

/// The metadata items the output movie carries at the movie level.
enum WriterMetadata {
    static func items(source: AVAsset, settings: EncodeSettings) async -> [AVMetadataItem] {
        guard settings.keepMetadata else { return [] }
        return (try? await source.load(.metadata)) ?? []
    }
}
