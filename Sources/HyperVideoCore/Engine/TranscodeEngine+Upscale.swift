@preconcurrency import AVFoundation
import Foundation

extension TranscodeEngine {
    /// AI Upscale: the frames go through Real-ESRGAN, the audio is copied as is.
    /// Uses the same work folder, space check and final move as a normal encode.
    func upscaleTranscode(
        source: URL, destination: URL, settings: EncodeSettings, upscale: UpscaleSettings,
        workTag: UUID?, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeOutput {
        guard let backend = upscaleBackend else { throw UpscaleError.backendMissing }
        let asset = AVURLAsset(url: source)
        let range = try Self.timeRange(settings.trim, duration: try await Self.readableDuration(of: asset))
        var info = try await MediaInspector.inspect(source)
        info.duration = range.duration.seconds
        let plan = UpscalePlan(info: info, settings: upscale)
        try precheckUpscaleSpace(plan: plan, destination: destination)

        let workDir = destination.deletingLastPathComponent().appendingPathComponent(WorkFolder.name(jobID: workTag))
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let container = Self.upscaleContainer(settings.container)
        let partial = workDir.appendingPathComponent(destination.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(container.fileExtension)
        let job = VideoUpscaler.Job(asset: asset, range: range, upscale: upscale, plan: plan, workDir: workDir,
                                    output: partial, fileType: container == .mov ? .mov : .mp4)
        try await VideoUpscaler(backend: backend).run(job, progress: progress)

        let final = try Self.moveIntoPlace(partial, destination: destination.deletingPathExtension()
            .appendingPathExtension(container.fileExtension), container: container)
        let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return TranscodeOutput(url: final, bytes: Int64(size ?? 0))
    }

    /// Upscaled files are MOV or MP4 (M4V and MKV become MP4).
    static func upscaleContainer(_ container: ContainerFormat) -> ContainerFormat {
        container == .mov ? .mov : .mp4
    }

    /// The output plus the intermediate video and one batch of frames.
    private func precheckUpscaleSpace(plan: UpscalePlan, destination: URL) throws {
        let frameBytes = Int64((plan.sourceSize.width * plan.sourceSize.height + plan.outputSize.width * plan.outputSize.height)
            * 2 * Double(VideoUpscaler.batchSize))
        let required = plan.predictedBytes * 2 + frameBytes
        guard let available = availableCapacity(destination.deletingLastPathComponent()), available < required else { return }
        throw TranscodeError.insufficientSpace(required: required, available: available)
    }
}
