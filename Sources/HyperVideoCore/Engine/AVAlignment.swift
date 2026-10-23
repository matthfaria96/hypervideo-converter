@preconcurrency import AVFoundation

/// Decides where the writer's session starts relative to the source timeline.
enum AVAlignment {
    static func sessionStart(asset: AVAsset, range: CMTimeRange, settings: EncodeSettings) async -> CMTime {
        guard settings.alignAVStart,
              let track = try? await asset.loadTracks(withMediaType: .video).first,
              let first = await firstFrameTime(asset: asset, track: track) else { return range.start }
        return start(rangeStart: range.start, firstVideo: first)
    }

    /// The later of the range start and the first video frame, so no audio plays before the picture.
    static func start(rangeStart: CMTime, firstVideo: CMTime?) -> CMTime {
        guard let firstVideo, firstVideo.isNumeric else { return rangeStart }
        return CMTimeMaximum(rangeStart, firstVideo)
    }

    /// Where the video track's first frame sits on the movie timeline: the later of the start
    /// of its first non-empty edit segment (a leading empty edit) and the earliest presentation
    /// time of its first samples (a B-frame or stream start offset with no edit list).
    private static func firstFrameTime(asset: AVAsset, track: AVAssetTrack) async -> CMTime? {
        let segments = (try? await track.load(.segments)) ?? []
        let editStart = segments.first { !$0.isEmpty }?.timeMapping.target.start
        let sampleStart = firstSampleTime(asset: asset, track: track)
        switch (editStart, sampleStart) {
        case let (edit?, sample?): return CMTimeMaximum(edit, sample)
        case let (edit, sample): return edit ?? sample
        }
    }

    /// The earliest presentation time, on the movie timeline, among the first few decoded
    /// video samples; nil when the track can't be read.
    private static func firstSampleTime(asset: AVAsset, track: AVAssetTrack) -> CMTime? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        var earliest: CMTime?
        // Enough samples to cover any decode reordering at the start.
        for _ in 0..<16 {
            guard let sample = output.copyNextSampleBuffer() else { break }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard CMSampleBufferGetNumSamples(sample) > 0, time.isNumeric else { continue }
            earliest = earliest.map { CMTimeMinimum($0, time) } ?? time
        }
        return earliest
    }
}
