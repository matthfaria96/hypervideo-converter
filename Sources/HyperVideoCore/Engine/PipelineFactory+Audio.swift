@preconcurrency import AVFoundation

extension PipelineFactory {
    func audioPumps(firstReportsProgress: Bool) async throws -> [SamplePump] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        var sources: [AudioSourceTrack] = []
        for track in tracks {
            // Most muxers write only the ISO 639-2 `mdhd` code, with no extended tag.
            let (tag, code) = try await track.load(.extendedLanguageTag, .languageCode)
            sources.append(AudioSourceTrack(id: Int(track.trackID), language: tag ?? code))
        }
        var pumps: [SamplePump] = []
        for job in AudioTrackPlanner.plan(sources: sources, settings: settings) {
            guard let track = tracks.first(where: { Int($0.trackID) == job.sourceTrackID }) else { continue }
            pumps.append(try await audioPump(for: track, job: job, reportsProgress: firstReportsProgress && pumps.isEmpty))
        }
        let inputs = pumps.map(\.input)
        groupAlternates(inputs, defaultInput: inputs.first)
        return pumps
    }

    func audioPump(for track: AVAssetTrack, job: AudioJob, reportsProgress: Bool) async throws -> SamplePump {
        let (formats, language, code) = try await track.load(.formatDescriptions, .extendedLanguageTag, .languageCode)
        let sourceFormat = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        var encoding = job.encoding
        if encoding.codec == .autoPassthru {
            let allowed = settings.audioOptions.allowedPassthru
            let copies = AutoPassthru.copies(formatID: sourceFormat?.mFormatID ?? 0, allowed: allowed, container: settings.container)
            if copies, writer.canAdd(AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)) {
                encoding.codec = .passthrough
            } else {
                encoding = AutoPassthru.fallbackEncoding(for: encoding, fallback: settings.audioOptions.fallback, container: settings.container)
            }
        }
        let copied = encoding.codec == .passthrough
        let (output, input, transform) = copied
            ? passthroughPump(track: track, formats: formats)
            : try encodedPump(track: track, encoding: encoding, sourceFormat: sourceFormat, label: job.label)
        input.extendedLanguageTag = language
        input.languageCode = code
        if let name = await trackName(for: encoding, track: track, copied: copied) {
            input.metadata = TrackNames.items(name)
        }
        return try attach(output: output, input: input, label: job.label, reportsProgress: reportsProgress, transform: transform)
    }

    private func passthroughPump(
        track: AVAssetTrack, formats: [CMFormatDescription]
    ) -> (AVAssetReaderOutput, AVAssetWriterInput, SampleTransform?) {
        (AVAssetReaderTrackOutput(track: track, outputSettings: nil),
         AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first), nil)
    }

    private func encodedPump(
        track: AVAssetTrack, encoding: AudioEncoding, sourceFormat: AudioStreamBasicDescription?, label: String
    ) throws -> (AVAssetReaderOutput, AVAssetWriterInput, SampleTransform?) {
        let sourceChannels = sourceFormat.map { Int($0.mChannelsPerFrame) } ?? 2
        let rate = encoding.sampleRate.resolved(sourceRate: sourceFormat?.mSampleRate ?? 48_000, codec: encoding.codec)
        var channels = encoding.mixdown.resolved(sourceChannels: sourceChannels).channelCount
        var settingsDict = OutputSettingsBuilder.audioWriter(encoding: encoding, channels: channels, sampleRate: rate)
        while !writer.canApply(outputSettings: settingsDict, forMediaType: .audio) && channels > 2 {
            channels = channels > 6 ? 6 : 2
            settingsDict = OutputSettingsBuilder.audioWriter(encoding: encoding, channels: channels, sampleRate: rate)
        }
        if !writer.canApply(outputSettings: settingsDict, forMediaType: .audio) {
            settingsDict[AVEncoderBitRateKey] = nil
        }
        guard writer.canApply(outputSettings: settingsDict, forMediaType: .audio) else {
            throw TranscodeError.cannotConfigure("\(label) encoding with these audio settings")
        }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: [track], audioSettings: OutputSettingsBuilder.audioReaderPCM(channels: channels, sampleRate: rate))
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settingsDict)
        return (output, input, AudioGain.transform(gainDb: encoding.gainDb))
    }

    private func trackName(for encoding: AudioEncoding, track: AVAssetTrack, copied: Bool) async -> String? {
        if let name = encoding.trackName, !name.isEmpty { return name }
        guard settings.audioOptions.automaticNaming else { return nil }
        return copied ? await TrackNames.name(of: track) : encoding.mixdown.displayName
    }
}
