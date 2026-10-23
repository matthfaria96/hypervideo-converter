import Foundation

extension HandBrakePresets {
    static func applySubtitles(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        s.subtitles = SubtitleSelection(rawValue: p.string("SubtitleTrackSelectionBehavior") ?? "") ?? .none
        s.subtitleOptions.languages = p.strings("SubtitleLanguageList").filter { $0 != "any" }
        if p.bool("SubtitleAddForeignAudioSearch") == true {
            notes.append("Foreign audio search isn't available.")
        }
        if ["first", "foreign_first"].contains(p.string("SubtitleBurnBehavior") ?? "none") {
            notes.append("Burned-in subtitles are chosen per video in the Subtitles tab.")
        }
    }

    static func applySummary(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        s.chapterOptions.markers = p.bool("ChapterMarkers")
        s.keepMetadata = p.bool("MetadataPassthrough") ?? s.keepMetadata
        s.alignAVStart = p.bool("AlignAVStart") ?? false
        s.optimizeForWeb = p.bool("Optimize") ?? p.bool("Mp4HttpOptimize") ?? s.optimizeForWeb
        if p.bool("Mp4iPodCompatible") == true {
            notes.append("iPod 5G support isn't available.")
        }
    }
}
