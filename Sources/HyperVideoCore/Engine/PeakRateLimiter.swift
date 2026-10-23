/// Drops frames so output never exceeds a peak rate (HandBrake's peak framerate mode).
struct PeakRateLimiter {
    let minimumInterval: Double
    private(set) var last: Double?
    private let tolerance = 0.0005

    init(peak: Double) {
        minimumInterval = peak > 0 ? 1 / peak : 0
    }

    /// True when a frame at `time` (seconds) keeps the rate at or under the peak.
    mutating func admits(_ time: Double) -> Bool {
        if let last, time - last < minimumInterval - tolerance { return false }
        last = time
        return true
    }
}
