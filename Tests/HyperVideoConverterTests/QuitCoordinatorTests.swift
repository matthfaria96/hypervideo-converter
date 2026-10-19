import AppKit
import Testing
@testable import HyperVideoConverter

@MainActor
private final class FakeQueue: QuitStoppable {
    var runningCount: Int
    private(set) var stopCalls = 0

    init(running: Int) { runningCount = running }

    func stopForQuit() async {
        stopCalls += 1
        await Task.yield()
        runningCount = 0
    }

    func stopImmediately() { runningCount = 0 }
}

@MainActor
@Suite("Quit coordinator")
struct QuitCoordinatorTests {
    @Test func quitsImmediatelyWhenIdle() {
        let coordinator = QuitCoordinator { Issue.record("should not re-terminate") }
        #expect(coordinator.shouldTerminate(queue: FakeQueue(running: 0)) == .terminateNow)
        #expect(coordinator.shouldTerminate(queue: nil) == .terminateNow)
    }

    @Test func terminateFromATaskDoesNotBlockAndQuitsAfterStopping() async throws {
        var terminations = 0
        let coordinator = QuitCoordinator { terminations += 1 }
        let queue = FakeQueue(running: 2)

        // Called from inside a main-actor Task, as `NSApp.terminate` from a Task would.
        let first = await Task { @MainActor in coordinator.shouldTerminate(queue: queue) }.value
        #expect(first == .terminateCancel)
        // A second request while stopping doesn't start another stop.
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateCancel)

        #expect(try await TestEnvironment.waitUntil(timeout: .seconds(5)) { terminations == 1 })
        #expect(queue.stopCalls == 1)
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateNow)
    }
}

@MainActor
private final class SyncQueue: QuitStoppable {
    var runningCount = 1
    var sessionEnding = false
    private(set) var immediateStops = 0
    private(set) var asyncStops = 0

    func stopForQuit() async { asyncStops += 1 }
    func stopImmediately() {
        immediateStops += 1
        runningCount = 0
    }
}

@MainActor
@Suite("Quit during logout or shutdown")
struct SessionEndQuitTests {
    @Test func sessionEndStopsSynchronouslyAndQuitsNow() {
        let coordinator = QuitCoordinator(terminate: { Issue.record("should not re-terminate") }, isSessionEnding: { true })
        let queue = SyncQueue()
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateNow)
        #expect(queue.immediateStops == 1)
        #expect(queue.asyncStops == 0)
    }

    @Test func sessionEndDuringAnAsyncStopQuitsNow() async throws {
        let state = SyncQueue()
        var terminations = 0
        let coordinator = QuitCoordinator(terminate: { terminations += 1 }, isSessionEnding: { state.sessionEnding })
        let queue = SyncQueue()
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateCancel)
        state.sessionEnding = true
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateNow)
        #expect(queue.immediateStops == 1)
        // The pending async stop must not terminate a second time.
        try await Task.sleep(for: .milliseconds(100))
        #expect(terminations == 0)
    }

    @Test func idleSessionEndDoesNothingSpecial() {
        let coordinator = QuitCoordinator(terminate: {}, isSessionEnding: { true })
        let queue = SyncQueue()
        queue.runningCount = 0
        #expect(coordinator.shouldTerminate(queue: queue) == .terminateNow)
        #expect(queue.immediateStops == 0)
    }

    @Test func quitReasonsAreRecognized() {
        func quitEvent(reason: String?) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(
                eventClass: SessionEndMonitor.fourCC("aevt"), eventID: SessionEndMonitor.fourCC("quit"),
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
            )
            if let reason {
                event.setAttribute(NSAppleEventDescriptor(enumCode: SessionEndMonitor.fourCC(reason)),
                                   forKeyword: SessionEndMonitor.fourCC("why?"))
            }
            return event
        }
        for reason in ["logo", "rlgo", "rrst", "rest", "rsdn", "shut"] {
            #expect(SessionEndMonitor.isSessionEnd(quitEvent(reason: reason)), "\(reason)")
        }
        #expect(!SessionEndMonitor.isSessionEnd(quitEvent(reason: nil)))
        #expect(!SessionEndMonitor.isSessionEnd(nil))
    }

    @Test func powerOffNotificationMarksTheSessionEnding() {
        let center = NotificationCenter()
        let monitor = SessionEndMonitor(center: center)
        #expect(!monitor.powerOffAnnounced)
        center.post(name: NSWorkspace.willPowerOffNotification, object: nil)
        #expect(monitor.powerOffAnnounced)
    }
}
