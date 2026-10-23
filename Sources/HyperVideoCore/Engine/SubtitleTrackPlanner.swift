import Foundation

struct SubtitleSourceTrack: Equatable, Sendable {
    let id: Int
    let kind: SubtitleTrackInfo.Kind
    let language: String?
    let forcedOnly: Bool
}

struct SubtitlePlanEntry: Equatable, Sendable {
    let sourceTrackID: Int
    let isDefault: Bool
    let forced: Bool
    let name: String?
}

struct SubtitlePlan: Equatable, Sendable {
    let entries: [SubtitlePlanEntry]
    /// Most source tracks to keep (the writer may refuse some); nil for no limit.
    let trackLimit: Int?
    /// The external file that is the default track, when no source track is.
    let defaultFileURL: URL?
}

/// Decides which source subtitle tracks are kept, and how external files are flagged.
enum SubtitleTrackPlanner {
    static func plan(sources: [SubtitleSourceTrack], files: [SubtitleFile], settings: EncodeSettings) -> SubtitlePlan {
        let candidates = sources.filter {
            $0.kind.isSupported(in: settings.container) && settings.burnIn != .track(id: $0.id)
        }
        let isExplicit = !settings.subtitleOptions.tracks.isEmpty
        let entries = isExplicit
            ? explicitEntries(candidates, settings: settings)
            : behaviourEntries(candidates, settings: settings)
        let limit = !isExplicit && settings.subtitles == .first ? 1 : nil
        let hasDefault = entries.contains(where: \.isDefault)
        let fileDefault = hasDefault ? nil : files.first { $0.isDefault && settings.burnIn != .file($0.url) }?.url
        return SubtitlePlan(entries: entries, trackLimit: limit, defaultFileURL: fileDefault)
    }

    private static func behaviourEntries(_ candidates: [SubtitleSourceTrack], settings: EncodeSettings) -> [SubtitlePlanEntry] {
        guard settings.subtitles != .none else { return [] }
        return candidates
            .filter { LanguageFilter.matches($0.language, in: settings.subtitleOptions.languages) }
            .map { SubtitlePlanEntry(sourceTrackID: $0.id, isDefault: false, forced: false, name: nil) }
    }

    private static func explicitEntries(_ candidates: [SubtitleSourceTrack], settings: EncodeSettings) -> [SubtitlePlanEntry] {
        var defaultTaken = false
        var entries: [SubtitlePlanEntry] = []
        for source in candidates {
            guard let setting = settings.subtitleOptions.tracks.first(where: { $0.sourceTrackID == source.id }),
                  setting.include, !setting.forcedOnly || source.forcedOnly else { continue }
            // Only text subtitles join the alternate group, so a caption can't be its default.
            let isDefault = setting.isDefault && !defaultTaken && source.kind == .subtitle
            defaultTaken = defaultTaken || isDefault
            let name = setting.name.flatMap { $0.isEmpty ? nil : $0 }
            entries.append(SubtitlePlanEntry(sourceTrackID: source.id, isDefault: isDefault,
                                             forced: setting.forcedOnly, name: name))
        }
        return entries
    }
}
