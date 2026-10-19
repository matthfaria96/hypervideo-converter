@preconcurrency import AVFoundation

/// Wires reader outputs to writer inputs for every track the settings keep.
struct PipelineFactory {
    let asset: AVURLAsset
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let settings: EncodeSettings
    let subtitleFiles: [SubtitleFile]

    /// A text track to keep: one of the source's own, or an external file.
    private enum SubtitleSource {
        case track(AVAssetTrack, SubtitleTrackInfo.Kind)
        case file(SubtitleFile)

        var kind: SubtitleTrackInfo.Kind {
            switch self {
            case .track(_, let kind): kind
            case .file: .subtitle
            }
        }
    }

    func makePumps() async throws -> [SamplePump] {
        var pumps: [SamplePump] = []
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            pumps.append(try await videoPump(for: video, subtitles: try await burner()))
        }
        var audio: [AVAssetWriterInput] = []
        for (index, track) in try await selectedAudioTracks().enumerated() {
            for (version, encoding) in settings.audioEncodings.enumerated() {
                let pump = try await audioPump(for: track, encoding: encoding, label: "audio\(index).\(version)",
                                               reportsProgress: pumps.isEmpty)
                pumps.append(pump)
                audio.append(pump.input)
            }
        }
        var subtitles: [AVAssetWriterInput] = []
        let sources = try await subtitleCandidates()
        for (index, source) in sources.enumerated() {
            let pump: SamplePump?
            switch source {
            case .track(let track, _):
                // `.first` keeps the first source track the writer accepts; candidates
                // are tracks before files, so `subtitles` holds only tracks here.
                let full = settings.subtitles == .first && !subtitles.isEmpty
                pump = full ? nil : try await subtitlePump(for: track, index: index)
            case .file(let file):
                pump = try subtitlePump(for: file, index: index)
            }
            if let pump {
                pumps.append(pump)
                subtitles.append(pump.input)
            }
        }
        if let main = pumps.first?.input, let pump = try await chapterPump(attachedTo: main) {
            pumps.append(pump)
        }
        groupAlternates(audio, defaultInput: audio.first)
        groupAlternates(subtitles.filter { $0.mediaType == .subtitle }, defaultInput: nil)
        return pumps
    }

    /// Puts tracks of one kind in an alternate group so players offer them as choices
    /// and play only the default (the first audio track; no subtitles until picked),
    /// rather than mixing every enabled audio track together.
    private func groupAlternates(_ inputs: [AVAssetWriterInput], defaultInput: AVAssetWriterInput?) {
        guard inputs.count > 1 || (defaultInput == nil && !inputs.isEmpty) else { return }
        for input in inputs where input !== defaultInput { input.marksOutputTrackAsEnabled = false }
        let group = AVAssetWriterInputGroup(inputs: inputs, defaultInput: defaultInput)
        if writer.canAdd(group) { writer.add(group) }
    }

    /// Source text tracks the container can hold (all of them unless the selection is
    /// `.none`; `makePumps` applies `.first`), then every external file the user added.
    private func subtitleCandidates() async throws -> [SubtitleSource] {
        // A burned-in subtitle is part of the picture, so it isn't also kept as a track.
        let files = subtitleFiles.filter { settings.burnIn != .file($0.url) }.map(SubtitleSource.file)
        guard settings.subtitles != .none else { return files }
        let tracks = try await MediaInspector.subtitleTracks(in: asset)
            .filter { settings.burnIn != .track(id: Int($0.0.trackID)) }
            .map { SubtitleSource.track($0.0, $0.1) }
        return SubtitleTrackInfo.kept(tracks, kind: \.kind, selection: .all, container: settings.container) + files
    }

    private func selectedAudioTracks() async throws -> [AVAssetTrack] {
        guard settings.audioCodec != .none else { return [] }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        return settings.audioTracks == .first ? Array(tracks.prefix(1)) : tracks
    }

    // MARK: Video

    /// The subtitle to burn in, cut to the trim range; nil when none is chosen.
    private func burner() async throws -> SubtitleBurner? {
        guard let burnIn = settings.burnIn, settings.videoCodec != .passthrough else { return nil }
        let range = reader.timeRange
        let cues = try await SubtitleBurner.cues(for: burnIn, asset: asset)
        return SubtitleBurner(cues: cues, start: range.start.seconds, end: range.end.seconds)
    }

    private func videoPump(for track: AVAssetTrack, subtitles: SubtitleBurner?) async throws -> SamplePump {
        let (natural, transform, fps, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
        )
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        if settings.videoCodec == .passthrough {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
            input.transform = transform
        } else {
            let plan = GeometryPlanner.plan(
                naturalSize: natural, preferredTransform: transform, crop: settings.crop,
                rotation: settings.rotation, flipHorizontal: settings.flipHorizontal,
                maxResolution: settings.maxResolution
            )
            let sourceColor = formats.first.flatMap(MediaInspector.colorSpace(of:))
            let color = OutputSettingsBuilder.outputColorSpace(for: settings.videoCodec, source: sourceColor)
            let sourceFPS = fps > 0 ? Double(fps) : nil

            let compositionOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track],
                videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: OutputSettingsBuilder.readerPixelFormat(for: settings.videoCodec)
                ]
            )
            let interlaced = formats.first.map(MediaInspector.isInterlaced) ?? false
            compositionOutput.videoComposition = try await composition(
                track: track, naturalSize: natural, plan: plan, sourceFPS: sourceFPS, color: color,
                deinterlace: settings.filters.deinterlaces(sourceIsInterlaced: interlaced),
                filtered: settings.filters.isActive(sourceIsInterlaced: interlaced) || subtitles != nil,
                subtitles: subtitles
            )
            output = compositionOutput
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: OutputSettingsBuilder.video(
                    settings: settings, renderSize: plan.renderSize, sourceFrameRate: sourceFPS, color: color
                )
            )
        }
        return try attach(output: output, input: input, label: "video", reportsProgress: true)
    }

    /// Plain geometry uses AVFoundation's own compositor; picture filters and burned-in
    /// subtitles switch to `FilterCompositor`, which applies them and the same geometry with Core Image.
    private func composition(
        track: AVAssetTrack, naturalSize: CGSize, plan: GeometryPlan, sourceFPS: Double?,
        color: OutputSettingsBuilder.ColorSpace, deinterlace: Bool, filtered: Bool, subtitles: SubtitleBurner?
    ) async throws -> AVVideoComposition {
        let duration = try await asset.load(.duration)
        let rate = settings.frameRate == .source ? (sourceFPS ?? 30) : settings.frameRate.rawValue
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        let instruction: any AVVideoCompositionInstructionProtocol
        if filtered {
            instruction = FilterInstruction(
                timeRange: timeRange, trackID: track.trackID, sourceSize: naturalSize, plan: plan,
                filters: settings.filters, deinterlace: deinterlace, subtitles: subtitles
            )
        } else {
            var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
            layer.setTransform(plan.transform, at: .zero)
            instruction = AVVideoCompositionInstruction(configuration: .init(
                layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
                timeRange: timeRange
            ))
        }
        return AVVideoComposition(configuration: .init(
            colorPrimaries: color.primaries,
            colorTransferFunction: color.transfer,
            colorYCbCrMatrix: color.matrix,
            customVideoCompositorClass: filtered ? FilterCompositor.self : nil,
            frameDuration: CMTime(value: 1_000, timescale: CMTimeScale((rate * 1_000).rounded())),
            instructions: [instruction],
            renderSize: plan.renderSize
        ))
    }

    // MARK: Audio

    private func audioPump(
        for track: AVAssetTrack, encoding: AudioEncoding, label: String, reportsProgress: Bool
    ) async throws -> SamplePump {
        let (formats, language) = try await track.load(.formatDescriptions, .extendedLanguageTag)
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        if encoding.codec == .passthrough {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)
        } else {
            let sourceChannels = formats.first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
                .map(Int.init) ?? 2
            let channels = encoding.mixdown.resolved(sourceChannels: sourceChannels).channelCount
            output = AVAssetReaderAudioMixOutput(
                audioTracks: [track], audioSettings: OutputSettingsBuilder.audioReaderPCM(channels: channels)
            )
            input = AVAssetWriterInput(
                mediaType: .audio, outputSettings: OutputSettingsBuilder.audioWriter(encoding: encoding, channels: channels)
            )
        }
        input.extendedLanguageTag = language
        return try attach(output: output, input: input, label: label, reportsProgress: reportsProgress)
    }

    // MARK: Subtitles

    /// Copies a text subtitle or caption track unchanged. Returns nil when the writer
    /// can't store this format in the chosen container, so one exotic track doesn't
    /// fail the whole encode.
    private func subtitlePump(for track: AVAssetTrack, index: Int) async throws -> SamplePump? {
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
    private func subtitlePump(for file: SubtitleFile, index: Int) throws -> SamplePump? {
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

    // MARK: Chapters

    /// Writes the source's chapters (cut to the trim range) as a disabled tx3g text
    /// track that `main` references as its chapter list, which is how MP4 and
    /// QuickTime players find chapters.
    private func chapterPump(attachedTo main: AVAssetWriterInput) async throws -> SamplePump? {
        guard settings.keepMetadata else { return nil }
        let range = reader.timeRange
        let chapters = Chapter.clipped(
            try await MediaInspector.chapters(of: asset), start: range.start.seconds, end: range.end.seconds
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

    // MARK: Plumbing

    private func attach(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String, reportsProgress: Bool) throws -> SamplePump {
        output.alwaysCopiesSampleData = false
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(output) else { throw TranscodeError.cannotConfigure("\(label) decoding") }
        guard writer.canAdd(input) else { throw TranscodeError.cannotConfigure("\(label) encoding in \(settings.container.displayName)") }
        reader.add(output)
        writer.add(input)
        return SamplePump(output: output, input: input, label: label, reportsProgress: reportsProgress)
    }
}
