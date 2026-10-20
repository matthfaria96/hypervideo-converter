import Foundation
import Testing
@testable import HyperVideoConverter

@Suite("Dock throttle")
struct DockThrottleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func firstCallIsAccepted() {
        #expect(DockThrottle().accepts(now: start, force: false))
    }

    @Test func callsWithinTheIntervalAreRejected() {
        let throttle = DockThrottle().recording(start)
        #expect(!throttle.accepts(now: start.addingTimeInterval(0.1), force: false))
        #expect(throttle.accepts(now: start.addingTimeInterval(0.6), force: false))
    }

    @Test func forcedCallsAlwaysPassAndResetTheTimer() {
        let throttle = DockThrottle().recording(start)
        let forcedAt = start.addingTimeInterval(0.1)
        #expect(throttle.accepts(now: forcedAt, force: true))
        let after = throttle.recording(forcedAt)
        #expect(after.last == forcedAt)
        #expect(!after.accepts(now: start.addingTimeInterval(0.55), force: false))
        #expect(after.accepts(now: start.addingTimeInterval(0.65), force: false))
    }

    @Test func recordingReturnsACopy() {
        let original = DockThrottle()
        _ = original.recording(start)
        #expect(original.last == nil)
    }
}
