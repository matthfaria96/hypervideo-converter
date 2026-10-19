import AppKit

/// What quitting needs from the queue.
@MainActor
protocol QuitStoppable: AnyObject {
    var runningCount: Int { get }
    func stopForQuit() async
    /// Cancels encodes and cleans up at once, for when the session is ending.
    func stopImmediately()
}

extension QueueStore: QuitStoppable {}

/// Decides whether the app may quit now. With encodes running it cancels this attempt,
/// stops the queue asynchronously (so cancelled encodes clean up their work folders),
/// then asks to terminate again. It never returns `.terminateLater`: that waits in a
/// nested run loop, and when `terminate` is called from a Task on the main actor the
/// stop can never run there, so the app would hang.
///
/// Logout, restart and shutdown are different: cancelling the quit would cancel them
/// too, so the queue is stopped synchronously and the app quits right away.
@MainActor
final class QuitCoordinator {
    private enum Phase { case idle, stopping, ready }

    private var phase = Phase.idle
    private let terminate: @MainActor () -> Void
    private let isSessionEnding: @MainActor () -> Bool

    init(
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
        isSessionEnding: @escaping @MainActor () -> Bool = { false }
    ) {
        self.terminate = terminate
        self.isSessionEnding = isSessionEnding
    }

    func shouldTerminate(queue: QuitStoppable?) -> NSApplication.TerminateReply {
        if phase != .ready, let queue, queue.runningCount > 0 || phase == .stopping, isSessionEnding() {
            queue.stopImmediately()
            phase = .ready
            return .terminateNow
        }
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
                // A session-end quit may have finished the job meanwhile.
                guard phase == .stopping else { return }
                phase = .ready
                terminate()
            }
            return .terminateCancel
        }
    }
}

/// Tells a user quit apart from logout, restart or shutdown: the system posts
/// `willPowerOffNotification` first, and its quit Apple event carries the reason.
@MainActor
final class SessionEndMonitor {
    private(set) var powerOffAnnounced = false
    private var observer: (any NSObjectProtocol)?

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        observer = center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.powerOffAnnounced = true }
        }
    }

    var isSessionEnding: Bool {
        powerOffAnnounced || Self.isSessionEnd(NSAppleEventManager.shared().currentAppleEvent)
    }

    /// `keyAEQuitReason` ('why?') values sent with logout, restart and shutdown.
    nonisolated static let sessionEndReasons = Set(["logo", "rlgo", "rrst", "rest", "rsdn", "shut"].map(fourCC))

    static func isSessionEnd(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == fourCC("aevt"), event.eventID == fourCC("quit") else { return false }
        let reason = event.attributeDescriptor(forKeyword: fourCC("why?")) ?? event.paramDescriptor(forKeyword: fourCC("why?"))
        guard let reason else { return false }
        return sessionEndReasons.contains(reason.enumCodeValue) || sessionEndReasons.contains(reason.typeCodeValue)
    }

    nonisolated static func fourCC(_ code: String) -> FourCharCode {
        code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
