import HyperVideoCore
import SwiftUI

/// Convert mode with no single video selected: the same eight tabs, editing the
/// selected videos, every video, or the next ones added.
struct AllVideosSettingsPanel: View {
    @Environment(AppModel.self) private var model

    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if model.inspectorTargetIDs.count > 1 && Self.perVideoTabs.contains(tab) {
                        Label("Track lists, chapter names, crop and trim stay per video. Select one video to change them.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SettingsTabContent(allVideos: model.allVideosSettingsBinding, info: model.panelReferenceInfo)
                        .id(tab)
                        .motionTransition(.content)
                }
                .padding(Spacing.l)
                .motion(value: tab)
            }
            .compatSoftScrollEdges()
        }
    }

    /// Tabs whose per-video parts don't change for every video at once.
    static let perVideoTabs: Set<SettingsTab> = [.dimensions, .audio, .subtitles, .chapters]

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label("Output Settings", systemImage: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            ScopeChip()
            PresetPicker()
            SettingsTabBar()
        }
        .padding(Spacing.l)
    }
}
