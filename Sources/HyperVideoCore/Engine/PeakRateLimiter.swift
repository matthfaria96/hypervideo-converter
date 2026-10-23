/// Drops frames so output never exceeds a peak rate (HandBrake's peak framerate mode).
/// Frames are admitted against an ideal grid of `1 / peak` slots, so a 50 fps source
/// with a 30 fps peak keeps about 30 frames a second rather than every other one.
struct PeakRateLimiter {
    let minimumInterval: Double
    /// The earliest time the next frame may be admitted; nil before the first frame.
    private(set) var nextSlot: Double?
    private let tolerance = 0.0005

    init(peak: Double) {
        minimumInterval = peak > 0 ? 1 / peak : 0
    }

    /// True when a frame at `time` (seconds) keeps the rate at or under the peak.
    mutating func admits(_ time: Double) -> Bool {
        if let nextSlot, time < nextSlot - tolerance { return false }
        let slot = nextSlot ?? time
        // Stay on the grid, but don't bank time across a pause in the source.
        nextSlot = time - slot > minimumInterval ? time + minimumInterval : slot + minimumInterval
        return true
    }
}
