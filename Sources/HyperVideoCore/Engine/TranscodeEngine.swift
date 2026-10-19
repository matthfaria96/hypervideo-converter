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
    /// `subtitleFiles` are external SRT/WebVTT files added after the source's own text tracks.
    public func run(
        source: URL,
        destination: URL,
        settings: EncodeSettings,
        subtitleFiles: [SubtitleFile] = [],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        guard settings.isValid else { throw TranscodeError.invalidSettings(settings.validationIssues) }

        let asset = AVURLAsset(url: source)
        let duration: CMTime
        do {
            // A missing, truncated or non-media file fails here with a bare AVFoundation error.
            let (readable, loaded) = try await asset.load(.isReadable, .duration)
            guard readable, loaded.isNumeric else { throw MediaInspectorError.unreadable(source) }
            duration = loaded
        } catch {
            throw TranscodeError.readerFailed("“\(source.lastPathComponent)” can't be opened (\(error.localizedDescription)).")
        }
        let range = try Self.timeRange(settings.trim, duration: duration)
        // Work in a private folder next to the output so cleanup also catches AVFoundation's sidecar files.
        let workDir = destination.deletingLastPathComponent().appendingPathComponent(".hypervideo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let partial = workDir.appendingPathComponent(destination.lastPathComponent)
        // MKV goes through an intermediate movie that is then remuxed; the encode is most of the work.
        let remuxes = settings.container == .mkv
        let encoded = remuxes ? workDir.appendingPathComponent("intermediate.mov") : partial
        let encodeShare = remuxes ? 0.9 : 1
        let encodeProgress: @Sendable (Double) -> Void = { progress($0 * encodeShare) }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: encoded, fileType: OutputSettingsBuilder.fileType(for: settings.container))
        writer.shouldOptimizeForNetworkUse = settings.optimizeForWeb && !remuxes
        if settings.keepMetadata {
            writer.metadata = (try? await asset.load(.metadata)) ?? []
        }

        let pumps = try await PipelineFactory(
            asset: asset, reader: reader, writer: writer, settings: settings, subtitleFiles: subtitleFiles
        ).makePumps()
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
        let watchdog = Task { [stallTimeout] in
            let interval = min(max(stallTimeout / 2, .milliseconds(1)), .seconds(1))
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if activity.idle > stallTimeout {
                    stalled.set()
                    cancel.set()
                    pumps.forEach { $0.abort() }
                    return
                }
            }
        }
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for pump in pumps {
                    group.addTask { await pump.run(range: range, cancel: cancel, activity: activity, progress: encodeProgress) }
                }
            }
        } onCancel: {
            cancel.set()
            pumps.forEach { $0.abort() }
        }
        watchdog.cancel()

        let userCancelled = Task.isCancelled
        if userCancelled || cancel.isSet || reader.status == .failed || writer.status == .failed {
            let readerError = reader.error?.localizedDescription
            let writerError = writer.error?.localizedDescription
            // Neither the reader nor the writer may be cancelled while a pump is inside
            // copyNextSampleBuffer or append, so cancel them with every pump queue held.
            // A pump stuck in a stall delays that until it returns; don't wait for it.
            let session = Unchecked((reader, writer))
            _ = await SamplePump.whenIdle(pumps, timeout: .seconds(2)) {
                session.value.0.cancelReading()
                session.value.1.cancelWriting()
            }
            if userCancelled { throw CancellationError() }
            if stalled.isSet { throw TranscodeError.stalled }
            if let writerError { throw TranscodeError.writerFailed(writerError) }
            throw TranscodeError.readerFailed(readerError ?? "unknown error")
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        if remuxes {
            try await remux(encoded, to: partial) { progress(encodeShare + $0 * (1 - encodeShare)) }
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

    /// Copies the finished intermediate movie into Matroska, stopping if the task is cancelled.
    private func remux(_ movie: URL, to output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let cancel = CancelFlag()
        try await withTaskCancellationHandler {
            try await MatroskaRemuxer(source: movie, destination: output).run(cancel: cancel, progress: progress)
        } onCancel: {
            cancel.set()
        }
        try? FileManager.default.removeItem(at: movie)
    }

    /// Shortest trim worth encoding: about one frame at 30 fps.
    static let minimumTrim = 1.0 / 30

    static func timeRange(_ trim: TrimRange?, duration: CMTime) throws -> CMTimeRange {
        guard let trim else { return CMTimeRange(start: .zero, duration: duration) }
        let total = duration.seconds
        let start = min(max(trim.start, 0), total)
        let end = min(trim.end ?? total, total)
        guard end - start >= minimumTrim else {
            throw TranscodeError.invalidSettings(["The trim range is too short to contain any video."])
        }
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: max(end, start), preferredTimescale: 600)
        )
    }
}

/// Hands non-Sendable AVFoundation objects to a closure that runs while no pump uses them.
final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
