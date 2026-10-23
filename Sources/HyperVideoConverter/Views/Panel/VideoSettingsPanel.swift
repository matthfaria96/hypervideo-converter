import HyperVideoCore
import SwiftUI

/// All HandBrake settings of one video, inline in the 460 pt right column.
struct VideoSettingsPanel: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem

    var body: some View {
        @Bindable var ui = model.ui
        VStack(spacing: 0) {
            header
            SettingsTabBar()
            Theme.separator.frame(height: 1)
            content
            footer
        }
        .environment(\.settingsLabelWidth, 128)
        .background(Theme.inspector)
        .alert("Save Preset", isPresented: $ui.isSavingPreset) {
            TextField("Name", text: $ui.presetName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the output settings shown in the inspector as a reusable preset.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Thumbnail(image: source.thumbnail, symbol: "film", isLoading: source.isLoading)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: model.presetName(for: source))
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { model.closePanel() } label: { Image(systemName: "xmark") }
                .buttonStyle(.subtle)
                .help("Back to the settings for all videos")
                .accessibilityLabel("Close")
        }
        .padding(18)
        .background(Theme.inspector)
    }

    @ViewBuilder
    private var content: some View {
        if let info = source.info {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !source.settings.validationIssues.isEmpty {
                        StatusBanner(messages: source.settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                    }
                    SettingsTabContent(source: source, info: info)
                }
                .padding(16)
            }
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
        .buttonStyle(.subtle)
        .padding(14)
        .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
    }

    private func saveCurrent() {
        let preset = model.presets.save(name: model.ui.presetName, category: String(localized: "My Presets"),
                                        settings: model.inspectorSettings)
        model.inspectorTargetIDs.forEach { id in model.update(id) { $0.presetID = preset.id } }
    }
}
