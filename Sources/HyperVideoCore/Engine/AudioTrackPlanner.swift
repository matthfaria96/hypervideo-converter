import AudioToolbox
import Foundation

struct AudioSourceTrack: Equatable, Sendable {
    let id: Int
    let language: String?
}

struct AudioJob: Equatable, Sendable {
    let sourceTrackID: Int
    let encoding: AudioEncoding
    let label: String
}

/// Decides which source audio tracks are encoded, and how.
enum AudioTrackPlanner {
    static func plan(sources: [AudioSourceTrack], settings: EncodeSettings) -> [AudioJob] {
        settings.audioOptions.tracks.isEmpty
            ? behaviourPlan(sources: sources, settings: settings)
            : explicitPlan(sources: sources, settings: settings)
    }

    private static func explicitPlan(sources: [AudioSourceTrack], settings: EncodeSettings) -> [AudioJob] {
        let ids = Set(sources.map(\.id))
        let usable = settings.audioOptions.tracks.filter { ids.contains($0.sourceTrackID) && $0.encoding.codec != .none }
        return usable.enumerated().map { index, setting in
            AudioJob(sourceTrackID: setting.sourceTrackID, encoding: setting.encoding, label: "audio\(index).0")
        }
    }

    private static func behaviourPlan(sources: [AudioSourceTrack], settings: EncodeSettings) -> [AudioJob] {
        let encodings = settings.audioEncodings
        guard !encodings.isEmpty, let firstSource = sources.first else { return [] }
        var chosen = sources.filter { LanguageFilter.matches($0.language, in: settings.audioOptions.languages) }
        if chosen.isEmpty { chosen = [firstSource] }
        if settings.audioTracks == .first { chosen = Array(chosen.prefix(1)) }
        var jobs: [AudioJob] = []
        for (index, source) in chosen.enumerated() {
            let versions = settings.audioOptions.extraFirstTrackOnly && index > 0 ? Array(encodings.prefix(1)) : encodings
            for (version, encoding) in versions.enumerated() {
                jobs.append(AudioJob(sourceTrackID: source.id, encoding: encoding, label: "audio\(index).\(version)"))
            }
        }
        return jobs
    }
}

/// Rules for Auto Passthru: copy only what the user allows and the container can carry.
enum AutoPassthru {
    static func copies(formatID: AudioFormatID, allowed: Set<PassthruCodec>, container: ContainerFormat) -> Bool {
        guard let codec = PassthruCodec.from(formatID: formatID), allowed.contains(codec) else { return false }
        return containerAccepts(codec, container)
    }

    static func containerAccepts(_ codec: PassthruCodec, _ container: ContainerFormat) -> Bool {
        switch container {
        case .mp4, .m4v: [.aac, .ac3, .eac3, .mp3].contains(codec)
        case .mov: [.aac, .ac3, .eac3, .mp3, .mp2, .alac].contains(codec)
        case .mkv: [.aac, .ac3, .eac3, .mp3, .alac].contains(codec)
        }
    }

    static func fallbackEncoding(for encoding: AudioEncoding, fallback: AudioCodec, container: ContainerFormat) -> AudioEncoding {
        var result = encoding
        switch fallback {
        case .alac: result.codec = container.supportsALAC ? .alac : .aac
        case .heAAC: result.codec = .heAAC
        default: result.codec = .aac
        }
        return result
    }
}
