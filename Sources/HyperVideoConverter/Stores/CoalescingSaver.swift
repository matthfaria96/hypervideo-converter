import Foundation

/// Saves a JSON document away from the main thread. Changes that arrive in a burst
/// (a progress tick, a reorder, a launch) become one write of the latest value.
final class CoalescingSaver<Value: Codable & Sendable>: @unchecked Sendable {
    private let store: JSONStore<Value>
    private let delay: TimeInterval
    private let queue = DispatchQueue(label: "com.hypervideo.converter.save", qos: .utility)
    private let lock = NSLock()
    private var pending: Value?
    private var isScheduled = false

    /// With a `delay` of zero or less every save is written right away, on the caller's
    /// thread (tests that read the file back).
    init(store: JSONStore<Value>, delay: TimeInterval = 0.5) {
        self.store = store
        self.delay = delay
    }

    func save(_ value: Value) {
        guard delay > 0 else {
            store.save(value)
            return
        }
        lock.lock()
        pending = value
        let needsTimer = !isScheduled
        isScheduled = true
        lock.unlock()
        if needsTimer { queue.asyncAfter(deadline: .now() + delay) { [self] in write() } }
    }

    /// Writes whatever is waiting and returns once it is on disk (quit, logout).
    func flush() {
        guard delay > 0 else { return }
        queue.sync { write() }
    }

    private func write() {
        lock.lock()
        let value = pending
        pending = nil
        isScheduled = false
        lock.unlock()
        if let value { store.save(value) }
    }
}
