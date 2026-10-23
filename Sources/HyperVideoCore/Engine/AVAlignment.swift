@preconcurrency import AVFoundation

/// Decides where the writer's session starts relative to the source timeline.
enum AVAlignment {
    static func sessionStart(asset: AVAsset, range: CMTimeRange, settings: EncodeSettings) async -> CMTime {
        guard settings.alignAVStart,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let first = firstSampleTime(track: track, asset: asset, range: range) else { return range.start }
        return start(rangeStart: range.start, firstVideo: first)
    }

    /// The later of the range start and the first video frame, so no audio plays before the picture.
    static func start(rangeStart: CMTime, firstVideo: CMTime?) -> CMTime {
        guard let firstVideo, firstVideo.isNumeric else { return rangeStart }
        return CMTimeMaximum(rangeStart, firstVideo)
    }

    private static func firstSampleTime(track: AVAssetTrack, asset: AVAsset, range: CMTimeRange) -> CMTime? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let window = range.duration.isNumeric ? min(2, range.duration.seconds) : 2
        reader.timeRange = CMTimeRange(start: range.start, duration: CMTime(seconds: window, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        return output.copyNextSampleBuffer().map { CMSampleBufferGetPresentationTimeStamp($0) }
    }
}
