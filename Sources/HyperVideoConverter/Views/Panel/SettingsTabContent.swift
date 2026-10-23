import HyperVideoCore
import SwiftUI

/// The body of the selected tab, for one video (the panel and the ⌘E sheet) or for
/// every target video at once (the Convert panel with no single video selected).
struct SettingsTabContent: View {
    @Environment(AppModel.self) private var model
    let settings: Binding<EncodeSettings>
    let info: MediaInfo
    /// The video the tabs edit; nil when they edit all the targets.
    let sourceID: UUID?
    var subtitleFiles: [SubtitleFile] = []

    init(source: SourceItem, info: MediaInfo, settings: Binding<EncodeSettings>) {
        self.settings = settings
        self.info = info
        sourceID = source.id
        subtitleFiles = source.subtitleFiles
    }

    init(allVideos settings: Binding<EncodeSettings>, info: MediaInfo) {
        self.settings = settings
        self.info = info
        sourceID = nil
    }

    var body: some View {
        tab(settings)
            // One view identity per video: drafts, detections and other tab state never leak to the next one.
            .id(sourceID)
    }

    @ViewBuilder
    private func tab(_ settings: Binding<EncodeSettings>) -> some View {
        switch model.ui.detailTab {
        case .summary: SummarySettingsTab(info: info, sourceID: sourceID, settings: settings, subtitleFiles: subtitleFiles)
        case .dimensions: DimensionsSettingsTab(info: info, settings: settings)
        case .filters: FiltersSettingsTab(info: info, settings: settings)
        case .video: VideoSettingsTab(info: info, settings: settings)
        case .audio: AudioSettingsTab(info: info, settings: settings)
        case .subtitles: SubtitlesSettingsTab(info: info, settings: settings, sourceID: sourceID, files: subtitleFiles)
        case .chapters: ChaptersSettingsTab(info: info, settings: settings)
        case .tags: TagsSettingsTab(settings: settings)
        }
    }
}
