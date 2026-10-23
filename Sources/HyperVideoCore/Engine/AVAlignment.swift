@preconcurrency import AVFoundation

/// Decides where the writer's session starts relative to the source timeline.
enum AVAlignment {
    static func sessionStart(asset: AVAsset, range: CMTimeRange, settings: EncodeSettings) async -> CMTime {
        range.start
    }
}
