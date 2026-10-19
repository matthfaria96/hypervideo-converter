import AppKit

/// What quitting needs from the queue.
@MainActor
protocol QuitStoppable: AnyObject {
    var runningCount: Int { get }
    func stopForQuit() async
}

extension QueueStore: QuitStoppable {}

/// Decides whether the app may quit now. With encodes running it cancels this attempt,
/// stops the queue asynchronously (so cancelled encodes clean up their work folders),
/// then asks to terminate again. It never returns `.terminateLater`: that waits in a
/// nested run loop, and when `terminate` is called from a Task on the main actor the
/// stop can never run there, so the app would hang.
@MainActor
final class QuitCoordinator {
    private enum Phase { case idle, stopping, ready }

    private var phase = Phase.idle
    private let terminate: @MainActor () -> Void

    init(terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.terminate = terminate
    }

    func shouldTerminate(queue: QuitStoppable?) -> NSApplication.TerminateReply {
        switch phase {
        case .ready:
            return .terminateNow
        case .stopping:
            return .terminateCancel
        case .idle:
            guard let queue, queue.runningCount > 0 else { return .terminateNow }
            phase = .stopping
            Task { @MainActor in
                await queue.stopForQuit()
                phase = .ready
                terminate()
            }
            return .terminateCancel
        }
    }
}
