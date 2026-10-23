@preconcurrency import AVFoundation
import CoreImage
import Synchronization

/// Everything `composition` needs to build the video composition for one track.
struct CompositionPlan {
    let track: AVAssetTrack
    let naturalSize: CGSize
    let plan: GeometryPlan
    let sourceFPS: Double?
    let color: OutputSettingsBuilder.ColorSpace
    let deinterlace: Bool
    let filtered: Bool
    let subtitles: SubtitleBurner?
    let canvas: CIColor
}

/// Keeps a `PeakRateLimiter` usable from a `@Sendable`-agnostic sample transform.
private final class PeakGate: @unchecked Sendable {
    private let limiter: Mutex<PeakRateLimiter>
    init(peak: Double) { limiter = Mutex(PeakRateLimiter(peak: peak)) }
    func admits(_ time: Double) -> Bool { limiter.withLock { $0.admits(time) } }
}

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
        guard settings.videoCodec != .passthrough else {
            return try passthroughVideoPump(track: track, transform: transform, format: formats.first)
        }
        let sourceFPS = fps > 0 ? Double(fps) : nil
        let plan = await geometryPlan(naturalSize: natural, transform: transform, format: formats.first)
        let sourceColor = formats.first.flatMap(MediaInspector.colorSpace(of:))
        let color = OutputSettingsBuilder.outputColorSpace(
            for: settings.videoCodec, source: sourceColor, target: settings.filters.colorspace
        )
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: OutputSettingsBuilder.readerPixelFormat(for: settings.videoCodec)
            ]
        )
        let interlaced = formats.first.map(MediaInspector.isInterlaced) ?? false
        let padding = settings.pictureOptions.padding
        output.videoComposition = try await composition(CompositionPlan(
            track: track, naturalSize: natural, plan: plan, sourceFPS: sourceFPS, color: color,
            deinterlace: settings.filters.deinterlaces(sourceIsInterlaced: interlaced),
            filtered: settings.filters.isActive(sourceIsInterlaced: interlaced) || subtitles != nil,
            subtitles: subtitles,
            canvas: CIColor(red: padding.red, green: padding.green, blue: padding.blue)
        ))
        let dictionary = OutputSettingsBuilder.video(
            settings: settings, renderSize: plan.renderSize, sourceFrameRate: sourceFPS, color: color,
            pixelAspect: plan.pixelAspect
        )
        guard writer.canApply(outputSettings: dictionary, forMediaType: .video) else {
            throw TranscodeError.cannotConfigure("video encoding with these encoder options in \(settings.container.displayName)")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: dictionary)
        let timing = Self.frameTiming(settings: settings, sourceFPS: sourceFPS)
        return try attach(
            output: output, input: input, label: "video", reportsProgress: true,
            transform: timing.peak.map(Self.peakTransform(peak:))
        )
    }

    /// Copies the compressed video unchanged, keeping its orientation.
    private func passthroughVideoPump(
        track: AVAssetTrack, transform: CGAffineTransform, format: CMFormatDescription?
    ) throws -> SamplePump {
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        input.transform = transform
        return try attach(output: output, input: input, label: "video", reportsProgress: true)
    }

    /// Crop, rotation, scaling, anamorphic and padding for this track and the job's settings.
    private func geometryPlan(
        naturalSize: CGSize, transform: CGAffineTransform, format: CMFormatDescription?
    ) async -> GeometryPlan {
        GeometryPlanner.plan(
            naturalSize: naturalSize, preferredTransform: transform, crop: await effectiveCrop(),
            rotation: settings.rotation, flipHorizontal: settings.flipHorizontal,
            maxResolution: settings.maxResolution, picture: settings.pictureOptions,
            sourcePixelAspect: format.flatMap(Self.pixelAspect(of:)) ?? CGSize(width: 1, height: 1)
        )
    }

    /// Borders to remove: detected on sampled frames for automatic/conservative, else the user's crop.
    func effectiveCrop() async -> Crop {
        switch settings.pictureOptions.cropMode {
        case .custom: return settings.crop
        case .none: return .zero
        case .automatic, .conservative:
            let detected = try? await CropDetector.detect(
                asset: asset, mode: settings.pictureOptions.cropMode, range: reader.timeRange, samples: 10
            )
            return detected?.rotated(by: settings.rotation, flipped: settings.flipHorizontal) ?? .zero
        }
    }

    /// Output frame timing: constant retimes to `rate`; variable follows the source's own
    /// timestamps; peak follows the source but drops frames above `peak`.
    static func frameTiming(settings: EncodeSettings, sourceFPS: Double?) -> (followsSource: Bool, rate: Double, peak: Double?) {
        let source = sourceFPS ?? 30
        let chosen = settings.frameRate == .source ? nil : settings.frameRate.rawValue
        switch settings.videoOptions.frameRateMode {
        case .constant: return (false, chosen ?? source, nil)
        case .variable: return (true, source, nil)
        case .peak: return (true, source, chosen)
        }
    }

    private static func peakTransform(peak: Double) -> SampleTransform {
        let gate = PeakGate(peak: peak)
        return { buffer in
            gate.admits(CMSampleBufferGetPresentationTimeStamp(buffer).seconds) ? buffer : nil
        }
    }

    /// The pixel aspect ratio the source declares; nil when absent or invalid.
    static func pixelAspect(of format: CMFormatDescription) -> CGSize? {
        let value = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_PixelAspectRatio)
        guard let dict = value as? [String: Any],
              let h = dict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber,
              let v = dict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber,
              h.doubleValue > 0, v.doubleValue > 0 else { return nil }
        return CGSize(width: h.doubleValue, height: v.doubleValue)
    }

    /// Plain geometry uses AVFoundation's own compositor; picture filters and burned-in
    /// subtitles switch to `FilterCompositor`, which applies them and the same geometry with Core Image.
    func composition(_ job: CompositionPlan) async throws -> AVVideoComposition {
        let duration = try await asset.load(.duration)
        let timing = Self.frameTiming(settings: settings, sourceFPS: job.sourceFPS)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        let instruction: any AVVideoCompositionInstructionProtocol
        if job.filtered {
            instruction = FilterInstruction(
                timeRange: timeRange, trackID: job.track.trackID, sourceSize: job.naturalSize, plan: job.plan,
                filters: settings.filters, deinterlace: job.deinterlace, subtitles: job.subtitles, canvas: job.canvas
            )
        } else {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: job.track)
            layer.setTransform(job.plan.transform, at: .zero)
            let plain = AVMutableVideoCompositionInstruction()
            plain.timeRange = timeRange
            plain.layerInstructions = [layer]
            if settings.pictureOptions.padding.isActive {
                plain.backgroundColor = CGColor(srgbRed: job.canvas.red, green: job.canvas.green, blue: job.canvas.blue, alpha: 1)
            }
            instruction = plain
        }
        // Pre-macOS 26 mutable API (deployment target is macOS 15); same settings as the
        // macOS 26 Configuration initialiser.
        let composition = AVMutableVideoComposition()
        composition.colorPrimaries = job.color.primaries
        composition.colorTransferFunction = job.color.transfer
        composition.colorYCbCrMatrix = job.color.matrix
        composition.customVideoCompositorClass = job.filtered ? FilterCompositor.self : nil
        composition.frameDuration = CMTime(value: 1_000, timescale: CMTimeScale((timing.rate * 1_000).rounded()))
        if timing.followsSource { composition.sourceTrackIDForFrameTiming = job.track.trackID }
        composition.instructions = [instruction]
        composition.renderSize = job.plan.renderSize
        guard let immutable = composition.copy() as? AVVideoComposition else { return composition }
        return immutable
    }
}
