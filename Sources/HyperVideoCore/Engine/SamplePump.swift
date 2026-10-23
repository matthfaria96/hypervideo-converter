@preconcurrency import AVFoundation
import Synchronization

/// Rewrites a sample between reader and writer; nil drops it.
typealias SampleTransform = (CMSampleBuffer) -> CMSampleBuffer?

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

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String, reportsProgress: Bool,
         transform: SampleTransform? = nil) {
        self.input = input
        self.reportsProgress = reportsProgress
        self.next = Self.filtered({ output.copyNextSampleBuffer() }, transform)
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

    /// Pulls samples from an arbitrary source; lets tests inject a stalled reader.
    init(next: @escaping () -> CMSampleBuffer?, input: AVAssetWriterInput, label: String,
         transform: SampleTransform? = nil) {
        self.input = input
        self.reportsProgress = false
        self.next = Self.filtered(next, transform)
        self.queue = DispatchQueue(label: "HyperVideo.pump.\(label)", qos: .userInitiated)
    }

    /// Wraps `source` so each buffer passes through `transform`; dropped buffers are
    /// skipped in a loop (no recursion), and a nil from `source` ends the stream.
    static func filtered(_ source: @escaping () -> CMSampleBuffer?, _ transform: SampleTransform?) -> () -> CMSampleBuffer? {
        guard let transform else { return source }
        return {
            while let buffer = source() {
                if let result = transform(buffer) { return result }
            }
            return nil
        }
    }

    /// True once a probe block enqueued on the pump queue has run within `timeout`,
    /// proving no earlier block is parked there.
    func drained(timeout: Duration) async -> Bool {
        let result = OneShot()
        queue.async { result.resume(true) }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            result.resume(false)
        }
        let value = await result.value()
        timer.cancel()
        return value
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

    /// Runs `work` exactly once, as soon as every pump's queue is idle and held, so
    /// nothing is inside the reader or writer while it runs. Returns true if that
    /// happened within `timeout`. If a pump is stuck inside the reader or writer past
    /// the deadline, `work` runs anyway: cancelling the reader and writer is what makes
    /// a stuck AVFoundation call return. The parked blocks are always released once
    /// every queue reaches them, so no GCD thread stays blocked.
    static func whenIdle(_ pumps: [SamplePump], timeout: Duration, work: @escaping @Sendable () -> Void) async -> Bool {
        let claimed = Mutex(false)
        let runOnce: @Sendable () -> Bool = {
            let first = claimed.withLock { claimed -> Bool in
                defer { claimed = true }
                return !claimed
            }
            if first { work() }
            return first
        }
        let parked = DispatchGroup()
        let release = DispatchSemaphore(value: 0)
        for pump in pumps {
            parked.enter()
            pump.queue.async {
                parked.leave()
                release.wait()
            }
        }
        let result = OneShot()
        parked.notify(queue: .global(qos: .utility)) {
            let ranHere = runOnce()
            for _ in pumps { release.signal() }
            result.resume(ranHere)
        }
        let timer = Task.detached {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            _ = runOnce()
            result.resume(false)
        }
        let idle = await result.value()
        timer.cancel()
        return idle
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

/// A Bool delivered exactly once to a single waiter; later results are ignored.
final class OneShot: Sendable {
    private struct State {
        var result: Bool?
        var waiter: CheckedContinuation<Bool, Never>?
    }
    private let state = Mutex(State())

    func resume(_ value: Bool) {
        let waiter: CheckedContinuation<Bool, Never>? = state.withLock { state in
            guard state.result == nil else { return nil }
            state.result = value
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: value)
    }

    func value() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let ready: Bool? = state.withLock { state in
                if let result = state.result { return result }
                state.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
