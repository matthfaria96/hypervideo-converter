@preconcurrency import AVFoundation

extension PipelineFactory {
    /// Writes the source's chapters (cut to the trim range) as a disabled tx3g text
    /// track that `main` references as its chapter list, which is how MP4 and
    /// QuickTime players find chapters.
    func chapterPump(attachedTo main: AVAssetWriterInput) async throws -> SamplePump? {
        guard settings.chapterOptions.writesMarkers(keepMetadata: settings.keepMetadata) else { return nil }
        let range = reader.timeRange
        let chapters = Chapter.clipped(
            Chapter.renamed(try await MediaInspector.chapters(of: asset), titles: settings.chapterOptions.titles), start: range.start.seconds, end: range.end.seconds
        )
        guard !chapters.isEmpty, let format = TimedText.format(mediaType: kCMMediaType_Text) else { return nil }
        let samples = chapters.compactMap { TimedText.sample($0.title, start: $0.start, duration: $0.duration, format: format) }

        let input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.marksOutputTrackAsEnabled = false
        input.expectsMediaDataInRealTime = false
        input.mediaDataLocation = .beforeMainMediaDataNotInterleaved
        let association = AVAssetTrack.AssociationType.chapterList.rawValue
        guard writer.canAdd(input), main.canAddTrackAssociation(withTrackOf: input, type: association) else { return nil }
        writer.add(input)
        main.addTrackAssociation(withTrackOf: input, type: association)
        return SamplePump(samples: samples, input: input, label: "chapters")
    }
}
