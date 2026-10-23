import SwiftUI

/// The eight HandBrake-style tabs of the Video Settings panel and the Advanced sheet.
enum SettingsTab: String, CaseIterable, Identifiable {
    case summary, dimensions, filters, video, audio, subtitles, chapters, tags
    var id: String { rawValue }

    /// ⌥⌘1…⌥⌘9 for the first nine tabs; later ones get no digit shortcut.
    static func shortcutDigit(at index: Int) -> Character? {
        (0..<9).contains(index) ? Character(String(index + 1)) : nil
    }

    var title: LocalizedStringKey {
        switch self {
        case .summary: "Summary"
        case .dimensions: "Dimensions"
        case .filters: "Filters"
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .chapters: "Chapters"
        case .tags: "Tags"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "doc.text.magnifyingglass"
        case .dimensions: "crop"
        case .filters: "camera.filters"
        case .video: "film"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        case .chapters: "list.bullet.indent"
        case .tags: "tag"
        }
    }
}
