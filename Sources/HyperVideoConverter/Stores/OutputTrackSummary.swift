import Foundation
import HyperVideoCore

/// What the output keeps, for the Summary's Before → After grid. Mirrors the core's
/// subtitle and audio track planners so the summary agrees with the encode.
extension EncodeSettings {
    /// Source subtitle tracks written as text tracks (external files not counted).
    func keptSubtitleTrackCount(info: MediaInfo) -> Int {
        let candidates = info.subtitleTracks.filter {
            $0.kind.isSupported(in: container) && burnIn != .track(id: $0.id)
        }
        guard subtitleOptions.tracks.isEmpty else {
            return candidates.filter { source in
                guard let setting = subtitleOptions.tracks.first(where: { $0.sourceTrackID == source.id }) else { return false }
                return setting.include && (!setting.forcedOnly || source.forcedOnly == true)
            }.count
        }
        guard subtitles != .none else { return 0 }
        let matching = candidates.filter { LanguageFilter.matches($0.language, in: subtitleOptions.languages) }.count
        return subtitles == .first ? min(1, matching) : matching
    }

    /// The encodings of the Audio tab's explicit track list, or nil when the selection
    /// behavior decides instead.
    func explicitAudioEncodings(info: MediaInfo) -> [AudioEncoding]? {
        guard !audioOptions.tracks.isEmpty else { return nil }
        let ids = Set(info.audioTracks.map(\.id))
        return audioOptions.tracks
            .filter { ids.contains($0.sourceTrackID) && $0.encoding.codec != .none }
            .map(\.encoding)
    }
}
