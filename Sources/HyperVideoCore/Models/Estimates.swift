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

        switch (settings.videoCodec, settings.rateControl) {
        case (.passthrough, _):
            guard info.duration > 0 else { return nil }
            return Int64((Double(info.fileBytes) * duration / info.duration).rounded())
        case (_, .averageBitrate(let kbps)) where settings.videoCodec.supportsRateControl:
            guard let audio = audioBitsPerSecond(info: info, settings: settings) else { return nil }
            return Int64((Double(kbps) * 1_000 / 8 * duration + audio / 8 * duration).rounded())
        default:
            return nil
        }
    }

    /// Combined audio bitrate of every planned audio job, nil when it can't be predicted.
    static func audioBitsPerSecond(info: MediaInfo, settings: EncodeSettings) -> Double? {
        var total = 0.0
        for (track, encoding) in audioJobs(info: info, settings: settings) {
            guard let rate = bitsPerSecond(of: resolved(encoding, track: track, settings: settings), track: track) else {
                return nil
            }
            total += rate
        }
        return total
    }

    /// The source track and encoding of each output audio track, as the engine plans them
    /// (explicit list, language filter, first/all and extra-version rules included).
    static func audioJobs(info: MediaInfo, settings: EncodeSettings) -> [(AudioTrackInfo, AudioEncoding)] {
        let sources = info.audioTracks.map { AudioSourceTrack(id: $0.id, language: $0.language) }
        return AudioTrackPlanner.plan(sources: sources, settings: settings).compactMap { job in
            info.audioTracks.first { $0.id == job.sourceTrackID }.map { ($0, job.encoding) }
        }
    }

    /// Auto Passthru becomes a copy only when the engine would copy this track's codec,
    /// otherwise the fallback encoder; other encodings are unchanged.
    static func resolved(_ encoding: AudioEncoding, track: AudioTrackInfo, settings: EncodeSettings) -> AudioEncoding {
        guard encoding.codec == .autoPassthru else { return encoding }
        let allowed = encoding.passthruOnly.map { Set([$0]) } ?? settings.audioOptions.allowedPassthru
        if let codec = PassthruCodec.from(codecName: track.codec), allowed.contains(codec),
           AutoPassthru.containerAccepts(codec, settings.container) {
            return encoding
        }
        return AutoPassthru.fallbackEncoding(for: encoding, fallback: settings.audioOptions.fallback, container: settings.container)
    }

    private static func bitsPerSecond(of encoding: AudioEncoding, track: AudioTrackInfo) -> Double? {
        switch encoding.codec {
        case .none:
            return 0
        case .aac, .heAAC:
            return Double(encoding.bitrateKbps * 1_000)
        case .passthrough, .autoPassthru:
            return track.bitrate
        case .alac:
            // Apple Lossless typically lands near 60% of 16-bit PCM.
            let channels = encoding.mixdown.resolved(sourceChannels: track.channels).channelCount
            return track.sampleRate * Double(channels) * 16 * 0.6
        }
    }
}
