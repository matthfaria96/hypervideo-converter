@preconcurrency import AVFoundation

/// The reader/writer half of an encode: one movie file from one source range.
struct EncodePass {
    let asset: AVURLAsset
    let range: CMTimeRange
    let output: URL
    let settings: EncodeSettings
    let subtitleFiles: [SubtitleFile]
}

extension TranscodeEngine {
    /// How the pumps ended.
    struct PumpOutcome {
        let userCancelled: Bool
        let cancelled: Bool
        let stalled: Bool
    }

    /// Reads, converts and writes `job.output`; throws on failure, cancellation or a stall.
    func encode(_ job: EncodePass, progress: @escaping @Sendable (Double) -> Void) async throws {
        let reader = try AVAssetReader(asset: job.asset)
        reader.timeRange = job.range
        let fileType = OutputSettingsBuilder.fileType(for: job.settings.container)
        let writer = try AVAssetWriter(outputURL: job.output, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = job.settings.optimizeForWeb && job.settings.container != .mkv
        writer.metadata = await WriterMetadata.items(source: job.asset, settings: job.settings)

        let sessionStart = await AVAlignment.sessionStart(asset: job.asset, range: job.range, settings: job.settings)
        let pumps = try await PipelineFactory(
            asset: job.asset, reader: reader, writer: writer, settings: job.settings, subtitleFiles: job.subtitleFiles
        ).makePumps()
        guard !pumps.isEmpty else { throw TranscodeError.noTracks }

        guard reader.startReading() else {
            throw TranscodeError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: sessionStart)

        let outcome = await runPumps(pumps, range: job.range, progress: progress)
        if outcome.userCancelled || outcome.cancelled || reader.status == .failed || writer.status == .failed {
            throw await abandon(reader: reader, writer: writer, pumps: pumps, outcome: outcome)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
    }

    /// Runs every pump to the end, with a watchdog that stops them all if none moves for `stallTimeout`.
    func runPumps(
        _ pumps: [SamplePump], range: CMTimeRange, progress: @escaping @Sendable (Double) -> Void
    ) async -> PumpOutcome {
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
                    group.addTask { await pump.run(range: range, cancel: cancel, activity: activity, progress: progress) }
                }
            }
        } onCancel: {
            cancel.set()
            pumps.forEach { $0.abort() }
        }
        watchdog.cancel()
        return PumpOutcome(userCancelled: Task.isCancelled, cancelled: cancel.isSet, stalled: stalled.isSet)
    }

    /// Cancels the reader and writer once no pump is inside them, and returns the error to report.
    func abandon(reader: AVAssetReader, writer: AVAssetWriter, pumps: [SamplePump], outcome: PumpOutcome) async -> any Error {
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
        if outcome.userCancelled { return CancellationError() }
        if outcome.stalled { return TranscodeError.stalled }
        if let failure = pumps.lazy.compactMap(\.failure).first { return failure }
        if let writerError { return TranscodeError.writerFailed(writerError) }
        return TranscodeError.readerFailed(readerError ?? "unknown error")
    }
}
