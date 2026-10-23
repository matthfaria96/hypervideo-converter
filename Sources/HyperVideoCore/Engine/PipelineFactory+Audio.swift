@preconcurrency import AVFoundation

extension PipelineFactory {
    func audioPumps(firstReportsProgress: Bool) async throws -> [SamplePump] {
        var pumps: [SamplePump] = []
        for (index, track) in try await selectedAudioTracks().enumerated() {
            for (version, encoding) in settings.audioEncodings.enumerated() {
                let pump = try await audioPump(for: track, encoding: encoding, label: "audio\(index).\(version)",
                                               reportsProgress: firstReportsProgress && pumps.isEmpty)
                pumps.append(pump)
            }
        }
        let inputs = pumps.map(\.input)
        groupAlternates(inputs, defaultInput: inputs.first)
        return pumps
    }

    func selectedAudioTracks() async throws -> [AVAssetTrack] {
        guard settings.audioCodec != .none else { return [] }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        return settings.audioTracks == .first ? Array(tracks.prefix(1)) : tracks
    }

    func audioPump(
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
}
