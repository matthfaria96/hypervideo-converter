@preconcurrency import AVFoundation

extension PipelineFactory {
    func subtitlePumps() async throws -> [SamplePump] {
        var pumps: [SamplePump] = []
        for (index, source) in try await subtitleCandidates().enumerated() {
            let pump: SamplePump?
            switch source {
            case .track(let track, _):
                // `.first` keeps the first source track the writer accepts; candidates
                // are tracks before files, so `pumps` holds only tracks here.
                let full = settings.subtitles == .first && !pumps.isEmpty
                pump = full ? nil : try await subtitlePump(for: track, index: index)
            case .file(let file):
                pump = try subtitlePump(for: file, index: index)
            }
            if let pump { pumps.append(pump) }
        }
        groupAlternates(pumps.map(\.input).filter { $0.mediaType == .subtitle }, defaultInput: nil)
        return pumps
    }

    /// Source text tracks the container can hold (all of them unless the selection is
    /// `.none`; `makePumps` applies `.first`), then every external file the user added.
    func subtitleCandidates() async throws -> [SubtitleSource] {
        // A burned-in subtitle is part of the picture, so it isn't also kept as a track.
        let files = subtitleFiles.filter { settings.burnIn != .file($0.url) }.map(SubtitleSource.file)
        guard settings.subtitles != .none else { return files }
        let tracks = try await MediaInspector.subtitleTracks(in: asset)
            .filter { settings.burnIn != .track(id: Int($0.0.trackID)) }
            .map { SubtitleSource.track($0.0, $0.1) }
        return SubtitleTrackInfo.kept(tracks, kind: \.kind, selection: .all, container: settings.container) + files
    }

    /// Copies a text subtitle or caption track unchanged. Returns nil when the writer
    /// can't store this format in the chosen container, so one exotic track doesn't
    /// fail the whole encode.
    func subtitlePump(for track: AVAssetTrack, index: Int) async throws -> SamplePump? {
        let (formats, language, code) = try await track.load(.formatDescriptions, .extendedLanguageTag, .languageCode)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: formats.first)
        input.extendedLanguageTag = language
        input.languageCode = code
        input.mediaDataLocation = .beforeMainMediaDataNotInterleaved
        guard reader.canAdd(output), writer.canAdd(input) else { return nil }
        return try attach(output: output, input: input, label: "subtitle\(index)", reportsProgress: false)
    }

    /// Writes an external subtitle file as a tx3g track, cut to the trim range.
    /// Files with no cues inside the range add no track; unreadable files fail the encode.
    func subtitlePump(for file: SubtitleFile, index: Int) throws -> SamplePump? {
        let cues: [SubtitleCue]
        do {
            cues = try SubtitleParser.cues(from: Data(contentsOf: file.url))
        } catch {
            throw TranscodeError.cannotConfigure("the subtitle file \(file.name) couldn't be read (\(error.localizedDescription))")
        }
        guard let format = TimedText.format(mediaType: kCMMediaType_Subtitle) else {
            throw TranscodeError.cannotConfigure("subtitle file \(file.name)")
        }
        let range = reader.timeRange
        let timeline = SubtitleParser.timeline(cues, start: range.start.seconds, end: range.end.seconds)
        guard timeline.contains(where: { !$0.text.isEmpty }) else { return nil }

        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
        input.extendedLanguageTag = file.language
        input.languageCode = file.language.flatMap { Locale(identifier: $0).language.languageCode?.identifier(.alpha3) }
        input.mediaDataLocation = .beforeMainMediaDataNotInterleaved
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        let samples = timeline.compactMap { TimedText.sample($0.text, start: $0.start, duration: $0.end - $0.start, format: format) }
        return SamplePump(samples: samples, input: input, label: "subtitle\(index)")
    }
}
