@preconcurrency import AVFoundation
import Synchronization

/// Thread-safe cancellation flag shared between the engine and its pumps.
final class CancelFlag: Sendable {
    private let state = Mutex(false)
    var isSet: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}

/// Moves samples from one reader output into one writer input on a private queue.
/// AVFoundation objects aren't Sendable, but each pump touches them only from `queue`.
final class SamplePump: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
    let reportsProgress: Bool
    private let queue: DispatchQueue
    private var finished = false
    private var lastReported = -1.0

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String, reportsProgress: Bool) {
        self.output = output
        self.input = input
        self.reportsProgress = reportsProgress
        self.queue = DispatchQueue(label: "HyperVideo.pump.\(label)", qos: .userInitiated)
    }

    func run(
        range: CMTimeRange,
        cancel: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    guard !cancel.isSet, let buffer = output.copyNextSampleBuffer() else {
                        finish(continuation)
                        return
                    }
                    report(buffer, range: range, progress: progress)
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

    private func finish(_ continuation: CheckedContinuation<Void, Never>) {
        guard !finished else { return }
        finished = true
        input.markAsFinished()
        continuation.resume()
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
