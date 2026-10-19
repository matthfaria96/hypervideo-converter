import HyperVideoCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case summary, video, dimensions, audio, subtitles, trim
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .summary: "Summary"
        case .video: "Video & Filters"
        case .dimensions: "Size & Crop"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        case .trim: "Trim & Preview"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "doc.text.magnifyingglass"
        case .video: "film"
        case .dimensions: "crop"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        case .trim: "timeline.selection"
        }
    }
}

/// Every detailed setting of one video (trim, crop, filters, tracks, chapters),
/// opened from the inspector's Advanced button or a row's context menu.
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
                    VStack(alignment: .leading, spacing: 16) {
                        if !source.settings.validationIssues.isEmpty {
                            StatusBanner(messages: source.settings.validationIssues.map { String(localized: String.LocalizationValue($0)) })
                        }
                        tabContent(info: info, source: source)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("No video selected", systemImage: "film",
                                       description: Text("Select one video in the list to edit its advanced settings."))
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 920, minHeight: 600, idealHeight: 700)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .animation(.smooth, value: tab)
    }

    private func header(_ source: SourceItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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
        .padding(20)
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
                Button("Apply to All Videos", systemImage: "square.on.square") { model.applyToAll(from: source.id) }
                    .help("Give every video in the list these settings (each keeps its own trim, crop and burned-in subtitle)")
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
        }
        .padding(16)
    }

    private func settings(_ id: UUID) -> Binding<EncodeSettings> {
        Binding(
            get: { model.sources.first { $0.id == id }?.settings ?? EncodeSettings() },
            set: { newValue in model.update(id) { $0.settings = newValue } }
        )
    }

    @ViewBuilder
    private func tabContent(info: MediaInfo, source: SourceItem) -> some View {
        let settings = settings(source.id)
        switch tab {
        case .summary: SummaryTab(info: info, settings: settings, subtitleFiles: source.subtitleFiles)
        case .video: VideoTab(info: info, settings: settings)
        case .dimensions: DimensionsTab(info: info, settings: settings)
        case .audio: AudioTab(info: info, settings: settings)
        case .subtitles: SubtitlesTab(info: info, settings: settings, sourceID: source.id, files: source.subtitleFiles)
        case .trim: TrimTab(info: info, settings: settings)
        }
    }
}
