import HyperVideoCore
import SwiftUI

/// All HandBrake settings of one video, inline in the inspector column.
struct VideoSettingsPanel: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem

    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        @Bindable var ui = model.ui
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .environment(\.settingsLabelWidth, 132)
        .alert("Save Preset", isPresented: $ui.isSavingPreset) {
            TextField("Name", text: $ui.presetName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this video's output settings as a reusable preset.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Thumbnail(image: source.thumbnail, symbol: "film", isLoading: source.isLoading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.headline)
                        .lineLimit(1).truncationMode(.middle)
                    Text(verbatim: model.presetName(for: source))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RowRemoveButton(help: "Back to the settings for all videos", label: String(localized: "Close")) {
                    model.closePanel()
                }
            }
            SettingsTabBar()
        }
        .padding(Spacing.l)
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
                    SettingsTabContent(source: source, info: info)
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

    private var footer: some View {
        HStack {
            if model.sources.count > 1 {
                ApplyToAllButton(sourceID: source.id)
            }
            Spacer()
            Button("Save as Preset…", systemImage: "square.and.arrow.down") {
                model.ui.presetName = ""
                model.ui.isSavingPreset = true
            }
        }
        .compatGlassButtonStyle()
        .controlSize(.small)
        .padding(Spacing.m)
    }

    private func saveCurrent() {
        model.saveAsPreset(name: model.ui.presetName, from: source.id)
    }
}
