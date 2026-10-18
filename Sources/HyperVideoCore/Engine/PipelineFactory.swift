@preconcurrency import AVFoundation

/// Wires reader outputs to writer inputs for every track the settings keep.
struct PipelineFactory {
    let asset: AVURLAsset
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let settings: EncodeSettings

    func makePumps() async throws -> [SamplePump] {
        var pumps: [SamplePump] = []
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            pumps.append(try await videoPump(for: video))
        }
        for (index, track) in try await selectedAudioTracks().enumerated() {
            pumps.append(try await audioPump(for: track, index: index, reportsProgress: pumps.isEmpty))
        }
        for (index, track) in try await selectedSubtitleTracks().enumerated() {
            if let pump = try await subtitlePump(for: track, index: index) { pumps.append(pump) }
        }
        return pumps
    }

    private func selectedSubtitleTracks() async throws -> [AVAssetTrack] {
        guard settings.subtitles != .none else { return [] }
        let tracks = try await MediaInspector.subtitleTracks(in: asset)
        return SubtitleTrackInfo.kept(tracks, kind: \.1, selection: settings.subtitles, container: settings.container)
            .map(\.0)
    }

    private func selectedAudioTracks() async throws -> [AVAssetTrack] {
        guard settings.audioCodec != .none else { return [] }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        return settings.audioTracks == .first ? Array(tracks.prefix(1)) : tracks
    }

    // MARK: Video

    private func videoPump(for track: AVAssetTrack) async throws -> SamplePump {
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
            compositionOutput.videoComposition = try await composition(
                track: track, plan: plan, sourceFPS: sourceFPS, color: color
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

    private func composition(
        track: AVAssetTrack, plan: GeometryPlan, sourceFPS: Double?, color: OutputSettingsBuilder.ColorSpace
    ) async throws -> AVVideoComposition {
        let duration = try await asset.load(.duration)
        let rate = settings.frameRate == .source ? (sourceFPS ?? 30) : settings.frameRate.rawValue

        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(plan.transform, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        ))
        return AVVideoComposition(configuration: .init(
            colorPrimaries: color.primaries,
            colorTransferFunction: color.transfer,
            colorYCbCrMatrix: color.matrix,
            frameDuration: CMTime(value: 1_000, timescale: CMTimeScale((rate * 1_000).rounded())),
            instructions: [instruction],
            renderSize: plan.renderSize
        ))
    }

    // MARK: Audio

    private func audioPump(for track: AVAssetTrack, index: Int, reportsProgress: Bool) async throws -> SamplePump {
        let (formats, language) = try await track.load(.formatDescriptions, .extendedLanguageTag)
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput

        if settings.audioCodec == .passthrough {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)
        } else {
            let sourceChannels = formats.first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
                .map(Int.init) ?? 2
            let channels = settings.audioMixdown.resolved(sourceChannels: sourceChannels).channelCount
            output = AVAssetReaderAudioMixOutput(
                audioTracks: [track], audioSettings: OutputSettingsBuilder.audioReaderPCM(channels: channels)
            )
            input = AVAssetWriterInput(
                mediaType: .audio, outputSettings: OutputSettingsBuilder.audioWriter(settings: settings, channels: channels)
            )
        }
        input.extendedLanguageTag = language
        return try attach(output: output, input: input, label: "audio\(index)", reportsProgress: reportsProgress)
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
        guard reader.canAdd(output), writer.canAdd(input) else { return nil }
        return try attach(output: output, input: input, label: "subtitle\(index)", reportsProgress: false)
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
