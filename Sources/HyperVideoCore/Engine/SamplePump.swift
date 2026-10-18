@preconcurrency import AVFoundation
import Synchronization

/// Thread-safe cancellation flag shared between the engine and its pumps.
final class CancelFlag: Sendable {
    private let state = Mutex(false)
    var isSet: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}

/// When any pump last appended a sample, so the engine can spot a stalled encode.
/// Uses the suspending clock so time the Mac spends asleep doesn't count as idle.
final class ActivityClock: Sendable {
    private let last = Mutex(SuspendingClock.now)
    func touch() { last.withLock { $0 = .now } }
    var idle: Duration { SuspendingClock.now - last.withLock { $0 } }
}

/// Moves samples from a source (a reader output or a prepared list) into one writer
/// input on a private queue. AVFoundation objects aren't Sendable, but each pump
/// touches them only from `queue`.
final class SamplePump: @unchecked Sendable {
    let input: AVAssetWriterInput
    let reportsProgress: Bool
    private let next: () -> CMSampleBuffer?
    private let queue: DispatchQueue
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var lastReported = -1.0

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String, reportsProgress: Bool) {
        self.input = input
        self.reportsProgress = reportsProgress
        self.next = { output.copyNextSampleBuffer() }
        self.queue = DispatchQueue(label: "HyperVideo.pump.\(label)", qos: .userInitiated)
    }

    /// Appends samples built up front, such as chapter titles.
    init(samples: [CMSampleBuffer], input: AVAssetWriterInput, label: String) {
        var remaining = samples.makeIterator()
        self.input = input
        self.reportsProgress = false
        self.next = { remaining.next() }
        self.queue = DispatchQueue(label: "HyperVideo.pump.\(label)", qos: .userInitiated)
    }

    func run(
        range: CMTimeRange,
        cancel: CancelFlag,
        activity: ActivityClock,
        progress: @escaping @Sendable (Double) -> Void
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in self.continuation = continuation }
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    guard !cancel.isSet, let buffer = next() else {
                        finish(continuation)
                        return
                    }
                    report(buffer, range: range, progress: progress)
                    activity.touch()
                    guard input.append(buffer) else {
                        // Writer rejected the sample; stop sibling pumps too.
                        cancel.set()
                        finish(continuation)
                        return
                    }
                }
            }
        }
    }

    private func finish(_ continuation: CheckedContinuation<Void, Never>, markingInput: Bool = true) {
        guard !finished else { return }
        finished = true
        if markingInput { input.markAsFinished() }
        continuation.resume()
    }

    /// Ends `run` even if the writer never asks for more data again. Call after
    /// cancelling the reader, which unblocks a pump waiting in `copyNextSampleBuffer`.
    func abort() {
        queue.async { [self] in
            if let continuation { finish(continuation, markingInput: false) }
        }
    }

    private func report(_ buffer: CMSampleBuffer, range: CMTimeRange, progress: @Sendable (Double) -> Void) {
        guard reportsProgress, range.duration.seconds > 0 else { return }
        let elapsed = (CMSampleBufferGetPresentationTimeStamp(buffer) - range.start).seconds
        let fraction = min(max(elapsed / range.duration.seconds, 0), 1)
        if fraction - lastReported >= 0.002 {
            lastReported = fraction
            progress(fraction)
        }
    }
}
