import HyperVideoCore
import SwiftUI

/// All HandBrake settings of one video, inline in the inspector column.
struct VideoSettingsPanel: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem
    @State private var confirmingApplyToAll = false

    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    /// The same header as every mode; the scope card shows this video.
    private var header: some View {
        PanelHeader {
            if model.sources.count > 1 { applyToAll }
            RowRemoveButton(help: "Back to the settings for all videos", label: String(localized: "Close")) {
                model.closePanel()
            }
        } extra: {
            PresetPicker()
            SettingsTabBar()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let info = source.info {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    if !source.settings.validationIssues.isEmpty {
                        StatusBanner(messages: source.settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                            .motionTransition(.pop)
                    }
                    SettingsTabContent(source: source, info: info, settings: model.settingsBinding(for: source.id))
                        .id(tab)
                        .motionTransition(.content)
                }
                .padding(Spacing.l)
                .motion(value: tab)
                .motion(value: source.settings.validationIssues)
            }
            .compatSoftScrollEdges()
        } else if let error = source.errorMessage {
            ContentUnavailableView("Can't read this video", systemImage: "exclamationmark.triangle",
                                   description: Text(verbatim: error))
        } else {
            ProgressView().frame(maxHeight: .infinity)
        }
    }

    /// Gives every other video this one's settings (each keeps its own trim, crop, tracks…).
    private var applyToAll: some View {
        Button {
            confirmingApplyToAll = true
        } label: {
            Image(systemName: "square.on.square")
        }
        .buttonStyle(.accessoryBar)
        .help("Apply to All Videos")
        .accessibilityLabel(Text("Apply to All Videos"))
        .confirmationDialog("Apply to all videos?", isPresented: $confirmingApplyToAll) {
            Button("Apply to All Videos") { model.applyToAll(from: source.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: model.applyToAllMessage(from: source.id))
        }
    }

}
