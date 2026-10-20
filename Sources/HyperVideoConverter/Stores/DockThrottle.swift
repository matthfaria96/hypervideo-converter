import Foundation

/// Limits how often the Dock tile redraws during progress ticks. Forced refreshes
/// (state changes) always pass, so the final state is never skipped.
struct DockThrottle: Sendable {
    let interval: TimeInterval = 0.5
    private(set) var last: Date?

    func accepts(now: Date, force: Bool) -> Bool {
        guard !force, let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// A copy that counts `now` as the latest refresh.
    func recording(_ now: Date) -> DockThrottle {
        var copy = self
        copy.last = now
        return copy
    }
}
