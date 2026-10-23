@preconcurrency import AVFoundation

extension PipelineFactory {
    func subtitlePumps() async throws -> [SamplePump] {
        let tracks = try await MediaInspector.subtitleTracks(in: asset)
        var sources: [SubtitleSourceTrack] = []
        for (track, kind) in tracks {
            let (formats, language, code) = try await track.load(.formatDescriptions, .extendedLanguageTag, .languageCode)
            let forced = await MediaInspector.isForcedOnly(track: track, format: formats.first)
            sources.append(SubtitleSourceTrack(id: Int(track.trackID), kind: kind, language: language ?? code, forcedOnly: forced))
        }
        let plan = SubtitleTrackPlanner.plan(sources: sources, files: subtitleFiles, settings: settings)

        var pumps: [SamplePump] = []
        var defaultInput: AVAssetWriterInput?
        var sourcePumps = 0
        for entry in plan.entries {
            if let limit = plan.trackLimit, sourcePumps >= limit { break }
            guard let track = tracks.first(where: { Int($0.0.trackID) == entry.sourceTrackID })?.0,
                  let pump = try await subtitlePump(for: track, index: pumps.count, name: entry.name) else { continue }
            sourcePumps += 1
            pumps.append(pump)
            if entry.isDefault { defaultInput = pump.input }
        }
        for file in subtitleFiles where settings.burnIn != .file(file.url) {
            guard let pump = try subtitlePump(for: file, index: pumps.count) else { continue }
            pumps.append(pump)
            if file.url == plan.defaultFileURL { defaultInput = pump.input }
        }
        groupAlternates(pumps.map(\.input).filter { $0.mediaType == .subtitle }, defaultInput: defaultInput)
        return pumps
    }

    /// Copies a text subtitle or caption track unchanged. Returns nil when the writer
    /// can't store this format in the chosen container, so one exotic track doesn't
    /// fail the whole encode.
    func subtitlePump(for track: AVAssetTrack, index: Int, name: String? = nil) async throws -> SamplePump? {
        let (formats, language, code) = try await track.load(.formatDescriptions, .extendedLanguageTag, .languageCode)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: formats.first)
        input.extendedLanguageTag = language
        input.languageCode = code
        input.mediaDataLocation = .beforeMainMediaDataNotInterleaved
        if let name, !name.isEmpty { input.metadata = TrackNames.items(name) }
        guard reader.canAdd(output), writer.canAdd(input) else { return nil }
        return try attach(output: output, input: input, label: "subtitle\(index)", reportsProgress: false)
    }

    /// Writes an external subtitle file as a tx3g track, cut to the trim range.
    /// Files with no cues inside the range add no track; unreadable files fail the encode.
    func subtitlePump(for file: SubtitleFile, index: Int) throws -> SamplePump? {
        let cues: [SubtitleCue]
        do {
            cues = SubtitleParser.shifted(try SubtitleParser.cues(from: Data(contentsOf: file.url)), byMs: file.offsetMs)
        } catch {
            throw TranscodeError.cannotConfigure("the subtitle file \(file.name) couldn't be read (\(error.localizedDescription))")
        }
        guard let format = TimedText.format(mediaType: kCMMediaType_Subtitle, forced: file.isForced) else {
            throw TranscodeError.cannotConfigure("subtitle file \(file.name)")
        }
        let range = reader.timeRange
        let timeline = SubtitleParser.timeline(cues, start: range.start.seconds, end: range.end.seconds)
        guard timeline.contains(where: { !$0.text.isEmpty }) else { return nil }

        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
        input.extendedLanguageTag = file.language
        input.languageCode = file.language.flatMap { Locale(identifier: $0).language.languageCode?.identifier(.alpha3) }
        if let title = file.title, !title.isEmpty { input.metadata = TrackNames.items(title) }
        input.mediaDataLocation = .beforeMainMediaDataNotInterleaved
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        let samples = timeline.compactMap { TimedText.sample($0.text, start: $0.start, duration: $0.end - $0.start, format: format) }
        return SamplePump(samples: samples, input: input, label: "subtitle\(index)")
    }
}
