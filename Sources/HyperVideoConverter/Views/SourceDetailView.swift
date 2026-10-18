import HyperVideoCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case summary = "Summary", video = "Video", dimensions = "Dimensions", audio = "Audio", trim = "Trim & Preview"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .summary: "doc.text.magnifyingglass"
        case .video: "film"
        case .dimensions: "crop"
        case .audio: "waveform"
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
                        tabContent(info: info)
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

    private var tabPicker: some View {
        Picker("Settings", selection: Bindable(model.ui).detailTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
    }

    @ViewBuilder
    private func tabContent(info: MediaInfo) -> some View {
        switch tab {
        case .summary: SummaryTab(info: info, settings: settings)
        case .video: VideoTab(info: info, settings: settings)
        case .dimensions: DimensionsTab(info: info, settings: settings)
        case .audio: AudioTab(info: info, settings: settings)
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
