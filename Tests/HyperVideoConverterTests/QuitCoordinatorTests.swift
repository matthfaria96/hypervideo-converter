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
