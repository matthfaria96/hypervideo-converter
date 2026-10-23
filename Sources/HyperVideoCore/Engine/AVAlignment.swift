@preconcurrency import AVFoundation

/// Decides where the writer's session starts relative to the source timeline.
enum AVAlignment {
    static func sessionStart(asset: AVAsset, range: CMTimeRange, settings: EncodeSettings) async -> CMTime {
        guard settings.alignAVStart,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let first = await firstFrameTime(track: track) else { return range.start }
        return start(rangeStart: range.start, firstVideo: first)
    }

    /// The later of the range start and the first video frame, so no audio plays before the picture.
    static func start(rangeStart: CMTime, firstVideo: CMTime?) -> CMTime {
        guard let firstVideo, firstVideo.isNumeric else { return rangeStart }
        return CMTimeMaximum(rangeStart, firstVideo)
    }

    /// Where the video track's first frame sits on the movie timeline: the start of its first
    /// non-empty edit segment. Sample timestamps alone are media time and miss a leading gap.
    private static func firstFrameTime(track: AVAssetTrack) async -> CMTime? {
        guard let segments = try? await track.load(.segments) else { return nil }
        return segments.first { !$0.isEmpty }?.timeMapping.target.start
    }
}
