@preconcurrency import AVFoundation

extension PipelineFactory {
    func videoPumps() async throws -> [SamplePump] {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        return [try await videoPump(for: video, subtitles: try await burner())]
    }

    /// The subtitle to burn in, cut to the trim range; nil when none is chosen.
    func burner() async throws -> SubtitleBurner? {
        guard let burnIn = settings.burnIn, settings.videoCodec != .passthrough else { return nil }
        let range = reader.timeRange
        let cues = try await SubtitleBurner.cues(for: burnIn, asset: asset)
        return SubtitleBurner(cues: cues, start: range.start.seconds, end: range.end.seconds)
    }

    func videoPump(for track: AVAssetTrack, subtitles: SubtitleBurner?) async throws -> SamplePump {
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
    func composition(
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
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(plan.transform, at: .zero)
            let plain = AVMutableVideoCompositionInstruction()
            plain.timeRange = timeRange
            plain.layerInstructions = [layer]
            instruction = plain
        }
        // Pre-macOS 26 mutable API (deployment target is macOS 15); same settings as the
        // macOS 26 Configuration initialiser.
        let composition = AVMutableVideoComposition()
        composition.colorPrimaries = color.primaries
        composition.colorTransferFunction = color.transfer
        composition.colorYCbCrMatrix = color.matrix
        composition.customVideoCompositorClass = filtered ? FilterCompositor.self : nil
        composition.frameDuration = CMTime(value: 1_000, timescale: CMTimeScale((rate * 1_000).rounded()))
        composition.instructions = [instruction]
        composition.renderSize = plan.renderSize
        guard let immutable = composition.copy() as? AVVideoComposition else { return composition }
        return immutable
    }
}
