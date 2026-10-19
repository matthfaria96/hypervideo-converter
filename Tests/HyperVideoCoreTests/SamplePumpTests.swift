@preconcurrency import AVFoundation
import Synchronization
import Testing
@testable import HyperVideoCore

@Suite("Sample pump")
struct SamplePumpTests {
    @Test func abortBeforeRunReturnsImmediately() async throws {
        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil,
                                       sourceFormatHint: TimedText.format(mediaType: kCMMediaType_Subtitle))
        let pump = SamplePump(samples: [], input: input, label: "test")
        pump.abort()
        let finished = Mutex(false)
        Task {
            await pump.run(range: CMTimeRange(start: .zero, duration: .zero), cancel: CancelFlag(),
                           activity: ActivityClock()) { _ in }
            finished.withLock { $0 = true }
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !finished.withLock({ $0 }) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(finished.withLock { $0 })
    }

    @Test func timeRangeRejectsLessThanAFrame() throws {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        #expect(throws: TranscodeError.self) { try TranscodeEngine.timeRange(TrimRange(start: 2, end: 2.01), duration: duration) }
        #expect(throws: TranscodeError.self) { try TranscodeEngine.timeRange(TrimRange(start: 12, end: nil), duration: duration) }
        #expect(try TranscodeEngine.timeRange(TrimRange(start: 2, end: 3), duration: duration).duration.seconds == 1)
        #expect(try TranscodeEngine.timeRange(nil, duration: duration).duration == duration)
    }
}
