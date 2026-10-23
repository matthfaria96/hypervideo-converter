import HyperVideoCore
import SwiftUI

/// The body of the selected tab, shared by the inline panel and the ⌘E sheet.
struct SettingsTabContent: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem
    let info: MediaInfo

    var body: some View {
        let settings = model.settingsBinding(for: source.id)
        switch model.ui.detailTab {
        case .summary: SummarySettingsTab(info: info, settings: settings, subtitleFiles: source.subtitleFiles)
        case .dimensions: DimensionsSettingsTab(info: info, settings: settings)
        case .filters: FiltersSettingsTab(info: info, settings: settings)
        case .video: VideoSettingsTab(info: info, settings: settings)
        case .audio: AudioSettingsTab(info: info, settings: settings)
        case .subtitles: SubtitlesSettingsTab(info: info, settings: settings, sourceID: source.id, files: source.subtitleFiles)
        case .chapters: ChaptersSettingsTab(info: info, settings: settings)
        case .tags: TagsSettingsTab(settings: settings)
        }
    }
}
