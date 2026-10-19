import HyperVideoCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case summary = "Summary", video = "Video", dimensions = "Dimensions", audio = "Audio"
    case subtitles = "Subtitles", trim = "Trim & Preview"
    var id: String { rawValue }
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

struct SourceDetailView: View {
    @Environment(AppModel.self) private var model
    let sourceID: UUID

    private var tab: SettingsTab { model.ui.detailTab }

    private var source: SourceItem? { model.sources.first { $0.id == sourceID } }

    private var settings: Binding<EncodeSettings> {
        Binding(
            get: { source?.settings ?? EncodeSettings() },
            set: { newValue in model.update(sourceID) { $0.settings = newValue } }
        )
    }

    var body: some View {
        if let source {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SourceHeaderView(source: source, presetName: model.presetName(for: source))
                    if let error = source.errorMessage {
                        StatusBanner(messages: [error])
                    } else if let info = source.info {
                        tabPicker
                        if !source.settings.validationIssues.isEmpty {
                            StatusBanner(messages: source.settings.validationIssues)
                        }
                        tabContent(info: info, source: source)
                    } else {
                        Label("Analyzing media…", systemImage: "rays")
                            .symbolEffect(.rotate)
                            .foregroundStyle(.secondary)
                            .padding(40)
                    }
                }
                .padding(24)
                .containerRelativeFrame(.horizontal)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaInset(edge: .bottom) {
                DestinationBar(source: source)
            }
            .navigationTitle(source.name)
            .navigationSubtitle(model.presetName(for: source))
            .animation(.smooth, value: tab)
        }
    }

    /// Titled segments when they fit, icons only in narrow windows.
    private var tabPicker: some View {
        ViewThatFits(in: .horizontal) {
            tabPicker(showsTitles: true)
            tabPicker(showsTitles: false)
        }
    }

    private func tabPicker(showsTitles: Bool) -> some View {
        Picker("Settings", selection: Bindable(model.ui).detailTab) {
            ForEach(SettingsTab.allCases) { tab in
                Group {
                    if showsTitles {
                        Label(tab.rawValue, systemImage: tab.symbol)
                    } else {
                        Image(systemName: tab.symbol).accessibilityLabel(tab.rawValue)
                    }
                }
                .help(tab.rawValue)
                .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
    }

    @ViewBuilder
    private func tabContent(info: MediaInfo, source: SourceItem) -> some View {
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

private struct DestinationBar: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    model.chooseDestination()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Save to").font(.caption).foregroundStyle(.secondary)
                            Text(model.destinationFolder.lastPathComponent).lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                    }
                }
                .buttonStyle(.glass)
                .help(model.destinationFolder.path)

                Spacer()

                if model.sources.count > 1 {
                    Button("Apply to All Sources", systemImage: "square.on.square") { model.applyToAll(from: source.id) }
                        .buttonStyle(.glass)
                }
                Button("Add to Queue", systemImage: "text.badge.plus") { model.enqueue([source.id]) }
                    .buttonStyle(.glass)
                    .keyboardShortcut("b")
                Button("Convert Now", systemImage: "bolt.fill") { model.encodeNow(source.id) }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .disabled(source.info == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
