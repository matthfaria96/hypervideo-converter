import HyperVideoCore
import SwiftUI

/// What the right column shows.
enum SettingsPanelKind: Equatable {
    /// Convert, one video: its eight tabs.
    case oneVideo
    /// Convert, several or no videos selected: the eight tabs for all of them.
    case allVideos
    /// Compress: the everyday choices only.
    case simple
    /// AI Upscale.
    case upscale
}

extension AppModel {
    var settingsPanelKind: SettingsPanelKind {
        switch mode {
        case .upscale: .upscale
        case .compress: .simple
        case .convert: panelSource == nil ? .allVideos : .oneVideo
        }
    }

    /// The tabs' settings when they edit every target video at once (the selection, or
    /// all videos, or the next ones added). Reading shows the first target's; writing
    /// gives every target the change, keeping each one's trim, crop, burned-in subtitle,
    /// track lists, chapter titles and title tag (as Apply to All does).
    var allVideosSettingsBinding: Binding<EncodeSettings> {
        Binding(
            get: { self.inspectorSettings },
            set: { newValue in self.editTargets { $0 = $0.copyingAll(from: newValue) } }
        )
    }

    /// Media facts the tabs describe when editing every video: the first target's, or an
    /// empty placeholder while the list is empty.
    var panelReferenceInfo: MediaInfo {
        let first = inspectorTargetIDs.lazy.compactMap { id in self.sources.first { $0.id == id }?.info }.first
        return first ?? MediaInfo(url: URL(fileURLWithPath: "/dev/null"), duration: 0, displaySize: nil, frameRate: nil,
                                  videoCodec: nil, videoBitrate: nil, dynamicRange: .sdr, audioTracks: [], fileBytes: 0)
    }
}

extension SettingsTab {
    /// The tab strip's two rows.
    static let rows: [[SettingsTab]] = [
        [.summary, .dimensions, .filters, .video],
        [.audio, .subtitles, .chapters, .tags],
    ]
}
