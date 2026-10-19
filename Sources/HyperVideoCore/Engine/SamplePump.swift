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
/// touches them only from `queue`; only the one-shot completion is shared.
final class SamplePump: @unchecked Sendable {
    let input: AVAssetWriterInput
    let reportsProgress: Bool
    private let next: () -> CMSampleBuffer?
    private let queue: DispatchQueue
    /// The waiting `run` call; taken exactly once, by whoever ends the pump first.
    private let completion = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let isDone = Mutex(false)
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
            // Checked under the same lock `takeCompletion` empties, so an abort that
            // lands before this point ends the run now instead of at the watchdog.
            let alreadyDone = completion.withLock { stored in
                if isDone.withLock({ $0 }) { return true }
                stored = continuation
                return false
            }
            if alreadyDone {
                continuation.resume()
                return
            }
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while !isDone.withLock({ $0 }) && input.isReadyForMoreMediaData {
                    guard !cancel.isSet, let buffer = next() else {
                        finish()
                        return
                    }
                    guard !isDone.withLock({ $0 }) else { return }
                    report(buffer, range: range, progress: progress)
                    activity.touch()
                    guard input.append(buffer) else {
                        // Writer rejected the sample; stop sibling pumps too.
                        cancel.set()
                        finish()
                        return
                    }
                }
            }
        }
    }

    /// Normal end, on `queue`: the input learns the track is complete.
    private func finish() {
        guard let continuation = takeCompletion() else { return }
        input.markAsFinished()
        continuation.resume()
    }

    /// Ends `run` from any thread without touching AVFoundation, for cancellation and
    /// stalls. A pump busy in the reader stops at its next step; one the writer never
    /// calls again is released right away.
    func abort() {
        takeCompletion()?.resume()
    }

    private func takeCompletion() -> CheckedContinuation<Void, Never>? {
        isDone.withLock { $0 = true }
        return completion.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }
    }

    /// Runs `work` once every pump's queue is idle and held, so nothing is inside the
    /// reader or writer while it runs. Returns true if that happened within `timeout`;
    /// otherwise `work` still runs later, whenever a stuck pump finally lets go.
    static func whenIdle(_ pumps: [SamplePump], timeout: Duration, work: @escaping @Sendable () -> Void) async -> Bool {
        let parked = DispatchGroup()
        let release = DispatchSemaphore(value: 0)
        for pump in pumps {
            parked.enter()
            pump.queue.async {
                parked.leave()
                release.wait()
            }
        }
        let ran = Mutex(false)
        parked.notify(queue: .global(qos: .utility)) {
            work()
            ran.withLock { $0 = true }
            for _ in pumps { release.signal() }
        }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if ran.withLock({ $0 }) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return ran.withLock { $0 }
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
