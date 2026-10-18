@preconcurrency import AVFoundation

public enum TranscodeError: LocalizedError {
    case invalidSettings([String])
    case noTracks
    case cannotConfigure(String)
    case readerFailed(String)
    case writerFailed(String)
    case stalled

    public var errorDescription: String? {
        switch self {
        case .invalidSettings(let issues): issues.joined(separator: "\n")
        case .noTracks: "The source has no tracks that can be converted."
        case .cannotConfigure(let what): "These settings aren't supported for this source: \(what)."
        case .readerFailed(let detail): "Couldn't decode the source: \(detail)"
        case .writerFailed(let detail): "Couldn't write the output: \(detail)"
        case .stalled: "The conversion stopped making progress, so it was stopped. Try again, or choose fewer subtitle or audio tracks."
        }
    }
}

/// Native transcoder built on AVAssetReader/AVAssetWriter with VideoToolbox hardware encoders.
public struct TranscodeEngine: Sendable {
    /// How long every track may go without writing a sample before the encode is
    /// treated as stuck. AVFoundation can deadlock when the reader and the writer's
    /// interleaving wait on each other; this turns a frozen queue into an error.
    let stallTimeout: Duration

    public init(stallTimeout: Duration = .seconds(60)) {
        self.stallTimeout = stallTimeout
    }

    /// Encodes `source` to `destination`, returning the output size in bytes.
    public func run(
        source: URL,
        destination: URL,
        settings: EncodeSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        guard settings.isValid else { throw TranscodeError.invalidSettings(settings.validationIssues) }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let range = Self.timeRange(settings.trim, duration: duration)
        // Work in a private folder next to the output so cleanup also catches AVFoundation's sidecar files.
        let workDir = destination.deletingLastPathComponent().appendingPathComponent(".hypervideo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let partial = workDir.appendingPathComponent(destination.lastPathComponent)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: partial, fileType: OutputSettingsBuilder.fileType(for: settings.container))
        writer.shouldOptimizeForNetworkUse = settings.optimizeForWeb
        if settings.keepMetadata {
            writer.metadata = (try? await asset.load(.metadata)) ?? []
        }

        let pumps = try await PipelineFactory(asset: asset, reader: reader, writer: writer, settings: settings).makePumps()
        guard !pumps.isEmpty else { throw TranscodeError.noTracks }

        guard reader.startReading() else {
            throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: range.start)

        let cancel = CancelFlag()
        let stalled = CancelFlag()
        let activity = ActivityClock()
        let stopper = Stopper(reader: reader, pumps: pumps)
        let watchdog = Task { [stallTimeout] in
            let interval = min(max(stallTimeout / 2, .milliseconds(1)), .seconds(1))
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if activity.idle > stallTimeout {
                    stalled.set()
                    cancel.set()
                    stopper.stop()
                    return
                }
            }
        }
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for pump in pumps {
                    group.addTask { await pump.run(range: range, cancel: cancel, activity: activity, progress: progress) }
                }
            }
        } onCancel: {
            cancel.set()
            stopper.stop()
        }
        watchdog.cancel()

        let userCancelled = Task.isCancelled
        if userCancelled || cancel.isSet || reader.status == .failed || writer.status == .failed {
            let readerError = reader.error?.localizedDescription
            let writerError = writer.error?.localizedDescription
            reader.cancelReading()
            writer.cancelWriting()
            if userCancelled { throw CancellationError() }
            if stalled.isSet { throw TranscodeError.stalled }
            if let writerError { throw TranscodeError.writerFailed(writerError) }
            throw TranscodeError.readerFailed(readerError ?? "unknown error")
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }

        do {
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            throw TranscodeError.writerFailed("Couldn't move the finished file into place (\(error.localizedDescription)).")
        }
        progress(1)
        let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? 0)
    }

    static func timeRange(_ trim: TrimRange?, duration: CMTime) -> CMTimeRange {
        guard let trim else { return CMTimeRange(start: .zero, duration: duration) }
        let total = duration.seconds
        let start = min(max(trim.start, 0), total)
        let end = min(trim.end ?? total, total)
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: max(end, start), preferredTimescale: 600)
        )
    }
}

/// Unblocks every pump: cancelling the reader makes a pump waiting for the next
/// sample see the end of the track, and `abort` releases pumps the writer never calls.
private final class Stopper: @unchecked Sendable {
    private let reader: AVAssetReader
    private let pumps: [SamplePump]

    init(reader: AVAssetReader, pumps: [SamplePump]) {
        self.reader = reader
        self.pumps = pumps
    }

    func stop() {
        reader.cancelReading()
        pumps.forEach { $0.abort() }
    }
}
