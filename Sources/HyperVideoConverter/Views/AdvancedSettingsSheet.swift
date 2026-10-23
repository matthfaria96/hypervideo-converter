import HyperVideoCore
import SwiftUI

/// Every detailed setting of one video in a large sheet (⌘E), for working with the
/// tabs at full width.
struct AdvancedSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var source: SourceItem? { model.sources.first { $0.id == model.ui.advancedSourceID } }
    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(spacing: 0) {
            if let source, let info = source.info {
                header(source)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if !source.settings.validationIssues.isEmpty {
                            StatusBanner(messages: source.settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                        }
                        SettingsTabContent(source: source, info: info)
                            .id(tab)
                            .motionTransition(.content)
                    }
                    .padding(Spacing.xl)
                    .motion(value: tab)
                }
            } else {
                ContentUnavailableView("No video selected", systemImage: "film",
                                       description: Text("Select one video in the list to edit its advanced settings."))
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 920, minHeight: 600, idealHeight: 700)
        .environment(\.settingsLabelWidth, 170)
    }

    private func header(_ source: SourceItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Thumbnail(image: source.thumbnail, symbol: "film", isLoading: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: model.presetName(for: source)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Titled segments when they fit, icons only otherwise.
            ViewThatFits(in: .horizontal) {
                tabPicker(showsTitles: true)
                tabPicker(showsTitles: false)
            }
        }
        .padding(Spacing.xl)
    }

    private func tabPicker(showsTitles: Bool) -> some View {
        Picker("Settings", selection: Bindable(model.ui).detailTab) {
            ForEach(SettingsTab.allCases) { tab in
                Group {
                    if showsTitles {
                        Text(tab.title)
                    } else {
                        Image(systemName: tab.symbol)
                    }
                }
                .help(tab.title)
                .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var footer: some View {
        HStack {
            if let source, model.sources.count > 1 {
                ApplyToAllButton(sourceID: source.id).compatGlassButtonStyle()
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .compatGlassProminentButtonStyle()
        }
        .padding(Spacing.l)
    }
}
