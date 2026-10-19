import Foundation
import Observation

/// How far one running job is. It lives apart from the job list, so a tick redraws only
/// the views that show this job's progress instead of everything that reads `jobs`.
@Observable
@MainActor
final class JobProgress {
    private(set) var fraction: Double = 0

    /// Progress only moves forward, even when ticks arrive out of order.
    func advance(to value: Double) {
        if value > fraction { fraction = value }
    }
}

/// Decides which progress ticks are worth showing: at most ~10 per second and only
/// when the bar moves by at least 1%. Called from the encoder's threads.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let minInterval: TimeInterval
    private let minStep: Double
    private var lastTime = -Double.infinity
    private var lastValue = -Double.infinity

    init(minInterval: TimeInterval = 0.1, minStep: Double = 0.01) {
        self.minInterval = minInterval
        self.minStep = minStep
    }

    func accepts(_ value: Double, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard time - lastTime >= minInterval, value - lastValue >= minStep else { return false }
        lastTime = time
        lastValue = value
        return true
    }
}
