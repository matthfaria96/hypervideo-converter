import Foundation

/// Live throughput of a running encode, derived from its progress and wall-clock time.
public struct EncodeRate: Equatable, Sendable {
    public var progress: Double
    public var elapsed: TimeInterval
    /// Seconds of media the encode produces in total (after trimming), when known.
    public var mediaDuration: Double?
    public var frameRate: Double?

    public init(progress: Double, elapsed: TimeInterval, mediaDuration: Double?, frameRate: Double?) {
        self.progress = progress
        self.elapsed = elapsed
        self.mediaDuration = mediaDuration
        self.frameRate = frameRate
    }

    /// Early readings swing wildly, so nothing is reported until the encode settles.
    private var isSettled: Bool { progress >= 0.01 && elapsed >= 1 }

    /// Media seconds encoded per wall-clock second ("3×" means three times realtime).
    public var speed: Double? {
        guard isSettled, let mediaDuration, mediaDuration > 0 else { return nil }
        return mediaDuration * progress / elapsed
    }

    public var framesPerSecond: Double? {
        guard let speed, let frameRate, frameRate > 0 else { return nil }
        return speed * frameRate
    }

    public var remaining: TimeInterval? {
        guard isSettled else { return nil }
        return elapsed * (1 - progress) / progress
    }
}

public extension EncodeSettings {
    /// Length of the output after trimming a source of `sourceDuration` seconds.
    func outputDuration(sourceDuration: Double) -> Double {
        guard let trim else { return sourceDuration }
        return max(0, min(trim.end ?? sourceDuration, sourceDuration) - max(0, trim.start))
    }

    /// Output frame rate, when it can be known before encoding.
    func outputFrameRate(sourceFrameRate: Double?) -> Double? {
        frameRate == .source || videoCodec == .passthrough ? sourceFrameRate : frameRate.rawValue
    }
}

/// Predicts output size where the settings make it predictable.
public enum OutputEstimate {
    /// Bytes for bitrate-driven or passthrough video; nil for constant quality, whose
    /// size depends on the content.
    public static func bytes(info: MediaInfo, settings: EncodeSettings) -> Int64? {
        let duration = settings.outputDuration(sourceDuration: info.duration)
        guard let audio = audioBitsPerSecond(info: info, settings: settings) else { return nil }
        let audioBytes = audio / 8 * duration

        switch (settings.videoCodec, settings.rateControl) {
        case (.passthrough, _):
            guard info.duration > 0 else { return nil }
            return Int64((Double(info.fileBytes) * duration / info.duration).rounded())
        case (_, .averageBitrate(let kbps)) where settings.videoCodec.supportsRateControl:
            return Int64((Double(kbps) * 1_000 / 8 * duration + audioBytes).rounded())
        default:
            return nil
        }
    }

    /// Combined audio bitrate of the kept tracks, nil when it can't be predicted.
    static func audioBitsPerSecond(info: MediaInfo, settings: EncodeSettings) -> Double? {
        let tracks = settings.audioTracks == .all ? info.audioTracks : Array(info.audioTracks.prefix(1))
        switch settings.audioCodec {
        case .none:
            return 0
        case .aac:
            return Double(settings.audioBitrateKbps * 1_000 * tracks.count)
        case .passthrough:
            let rates = tracks.map(\.bitrate)
            return rates.contains(nil) ? nil : rates.compactMap { $0 }.reduce(0, +)
        case .alac:
            // Apple Lossless typically lands near 60% of 16-bit PCM.
            return tracks.reduce(0) { total, track in
                let channels = settings.audioMixdown.resolved(sourceChannels: track.channels).channelCount
                return total + track.sampleRate * Double(channels) * 16 * 0.6
            }
        }
    }
}
