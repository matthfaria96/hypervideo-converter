@preconcurrency import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import HyperVideoCore

/// A source that blocks inside its first call, like a deadlocked copyNextSampleBuffer,
/// until the cancel work opens the gate.
private final class StalledSource: Sendable {
    let gate = DispatchSemaphore(value: 0)
    private let entered = Mutex(false)
    private let stalledOnce = Mutex(false)

    var hasEntered: Bool { entered.withLock { $0 } }

    func next() -> CMSampleBuffer? {
        entered.withLock { $0 = true }
        let first = stalledOnce.withLock { stalled -> Bool in
            defer { stalled = true }
            return !stalled
        }
        if first { gate.wait() }
        return nil
    }
}

private final class Counter: Sendable {
    private let state = Mutex(0)
    var value: Int { state.withLock { $0 } }
    func increment() { state.withLock { $0 += 1 } }
}

@Suite("Sample pump stalls", .serialized)
struct SamplePumpStallTests {
    private func makeWriterInput() throws -> (AVAssetWriter, AVAssetWriterInput, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stall-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil,
                                       sourceFormatHint: TimedText.format(mediaType: kCMMediaType_Subtitle))
        try #require(writer.canAdd(input))
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        return (writer, input, url)
    }

    private func waitUntil(_ timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Runs a pump into a stall, aborts it and calls whenIdle; returns the pump and work count.
    private func stall() async throws -> (SamplePump, Counter, StalledSource, AVAssetWriter, URL) {
        let (writer, input, url) = try makeWriterInput()
        let source = StalledSource()
        let pump = SamplePump(next: { source.next() }, input: input, label: "stall")
        let finished = Mutex(false)
        Task {
            await pump.run(range: CMTimeRange(start: .zero, duration: .zero), cancel: CancelFlag(),
                           activity: ActivityClock()) { _ in }
            finished.withLock { $0 = true }
        }
        #expect(try await waitUntil(.seconds(5)) { source.hasEntered })
        pump.abort()
        #expect(try await waitUntil(.seconds(2)) { finished.withLock { $0 } })
        let count = Counter()
        let gate = source.gate
        _ = await SamplePump.whenIdle([pump], timeout: .milliseconds(200)) {
            count.increment()
            gate.signal()
        }
        return (pump, count, source, writer, url)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelWorkRunsWhenAPumpIsStuck() async throws {
        let (_, count, source, writer, url) = try await stall()
        let ran = try await waitUntil(.seconds(1)) { count.value == 1 }
        #expect(ran)
        if !ran { source.gate.signal() }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    @Test(.timeLimit(.minutes(1)))
    func pumpQueuesDrainAfterStall() async throws {
        let (pump, count, source, writer, url) = try await stall()
        let drained = await pump.drained(timeout: .seconds(1))
        #expect(drained)
        try await Task.sleep(for: .milliseconds(300))
        #expect(count.value == 1)
        if !drained { source.gate.signal() }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    @Test(.timeLimit(.minutes(1)))
    func workRunsOnceWhenPumpsAreIdle() async throws {
        let (writer, input, url) = try makeWriterInput()
        let pump = SamplePump(samples: [], input: input, label: "idle")
        let count = Counter()
        let idle = await SamplePump.whenIdle([pump], timeout: .seconds(2)) { count.increment() }
        #expect(idle)
        try await Task.sleep(for: .milliseconds(300))
        #expect(count.value == 1)
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }
}
