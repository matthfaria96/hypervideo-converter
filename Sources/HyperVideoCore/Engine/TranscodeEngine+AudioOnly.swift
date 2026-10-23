@preconcurrency import AVFoundation
import Foundation

extension TranscodeEngine {
    /// "Audio only (M4A)": Apple's AAC export of the source's sound over the trim range.
    func audioOnlyTranscode(
        source: URL, destination: URL, settings: EncodeSettings, workTag: UUID?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeOutput {
        let asset = AVURLAsset(url: source)
        let range = try Self.timeRange(settings.trim, duration: try await Self.readableDuration(of: asset))
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw TranscodeError.noTracks }

        let workDir = destination.deletingLastPathComponent().appendingPathComponent(WorkFolder.name(jobID: workTag))
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let partial = workDir.appendingPathComponent(destination.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscodeError.cannotConfigure("Apple's audio export isn't available for this file.")
        }
        session.timeRange = range
        // Only the progress stream crosses into the watcher; the session stays here.
        let states = session.states(updateInterval: 0.2)
        let watcher = Task {
            for await state in states {
                if case .exporting(let progressValue) = state { progress(progressValue.fractionCompleted * 0.99) }
            }
        }
        defer { watcher.cancel() }
        try await session.export(to: partial, as: .m4a)

        let final = try Self.moveIntoPlace(partial, destination: destination.deletingPathExtension().appendingPathExtension("m4a"),
                                           container: .m4a)
        progress(1)
        let size = try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return TranscodeOutput(url: final, bytes: Int64(size ?? 0))
    }
}
