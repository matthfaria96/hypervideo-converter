import Foundation
import HyperVideoCore

/// Free-text language lists ("eng, por") to and from the stored arrays.
enum LanguageList {
    static func parse(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        var seen = Set<String>()
        return text.components(separatedBy: separators)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func format(_ list: [String]) -> String { list.joined(separator: ", ") }
}

// MARK: Audio track list

extension EncodeSettings {
    /// The encoding a newly added audio track starts with.
    var defaultTrackEncoding: AudioEncoding {
        audioEncodings.first ?? AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160)
    }

    func addingAudioTrack(from info: MediaInfo) -> EncodeSettings {
        guard !info.audioTracks.isEmpty else { return self }
        let used = Set(audioOptions.tracks.map(\.sourceTrackID))
        let source = info.audioTracks.first { !used.contains($0.id) } ?? info.audioTracks[0]
        return appendingAudioTracks([source.id])
    }

    func addingAllAudioTracks(from info: MediaInfo) -> EncodeSettings {
        let used = Set(audioOptions.tracks.map(\.sourceTrackID))
        return appendingAudioTracks(info.audioTracks.map(\.id).filter { !used.contains($0) })
    }

    func removingAudioTrack(_ id: UUID) -> EncodeSettings {
        var copy = self
        copy.audioOptions.tracks = audioOptions.tracks.filter { $0.id != id }
        return copy
    }

    func resettingAudioTracks() -> EncodeSettings {
        var copy = self
        copy.audioOptions.tracks = []
        return copy
    }

    private func appendingAudioTracks(_ ids: [Int]) -> EncodeSettings {
        var copy = self
        let encoding = defaultTrackEncoding
        copy.audioOptions.tracks = audioOptions.tracks + ids.map {
            AudioTrackSetting(sourceTrackID: $0, encoding: encoding)
        }
        return copy
    }
}

// MARK: Subtitle track list

extension EncodeSettings {
    /// The explicit per-track list: the stored one (missing tracks appended as not included),
    /// or the one the selection behavior and languages currently produce.
    func materializedSubtitleTracks(info: MediaInfo) -> [SubtitleTrackSetting] {
        let stored = subtitleOptions.tracks
        guard stored.isEmpty else {
            let known = Set(stored.map(\.sourceTrackID))
            let missing = info.subtitleTracks.filter { !known.contains($0.id) }
            return stored + missing.map { SubtitleTrackSetting(sourceTrackID: $0.id, include: false) }
        }
        let candidates = info.subtitleTracks.filter {
            LanguageFilter.matches($0.language, in: subtitleOptions.languages)
        }
        let kept = SubtitleTrackInfo.kept(candidates, kind: \.kind, selection: subtitles, container: container)
        let keptIDs = Set(kept.map(\.id))
        return info.subtitleTracks.map { SubtitleTrackSetting(sourceTrackID: $0.id, include: keptIDs.contains($0.id)) }
    }

    func updatingSubtitleTrack(
        _ id: Int, info: MediaInfo, _ change: (inout SubtitleTrackSetting) -> Void
    ) -> EncodeSettings {
        var copy = self
        copy.subtitleOptions.tracks = materializedSubtitleTracks(info: info).map { track in
            var edited = track
            if track.sourceTrackID == id { change(&edited) }
            return edited
        }
        guard let changed = copy.subtitleOptions.tracks.first(where: { $0.sourceTrackID == id }), changed.isDefault else {
            return copy
        }
        copy.subtitleOptions.tracks = copy.subtitleOptions.tracks.map { track in
            guard track.sourceTrackID != id, track.isDefault else { return track }
            var other = track
            other.isDefault = false
            return other
        }
        return copy
    }

    func resettingSubtitleTracks() -> EncodeSettings {
        var copy = self
        copy.subtitleOptions.tracks = []
        return copy
    }
}
