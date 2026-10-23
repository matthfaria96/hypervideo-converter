import HyperVideoCore
import SwiftUI

/// Every detailed setting of one video in a large sheet (⌘E): the video and its
/// before → after on the left, the eight tabs at full width on the right.
struct AdvancedSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var source: SourceItem? { model.sources.first { $0.id == model.ui.advancedSourceID } }
    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(spacing: 0) {
            if let source, let info = source.info {
                HStack(spacing: 0) {
                    VideoSummaryColumn(source: source, info: info)
                        .frame(width: 300)
                    Divider()
                    settings(source, info: info)
                }
            } else {
                ContentUnavailableView("No video selected", systemImage: "film",
                                       description: Text("Select one video in the list to edit its advanced settings."))
            }
            Divider()
            footer
        }
        .frame(minWidth: 1000, idealWidth: 1100, minHeight: 640, idealHeight: 760)
        .environment(\.settingsLabelWidth, 170)
        // AppKit focuses the first text field of a new sheet; start with nothing focused.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private func settings(_ source: SourceItem, info: MediaInfo) -> some View {
        VStack(spacing: 0) {
            tabPicker
                .padding(Spacing.l)
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
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .motion(value: tab)
            }
            .compatSoftScrollEdges()
        }
    }

    private var tabPicker: some View {
        Picker("Settings", selection: Bindable(model.ui).detailTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
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

/// The left column of the sheet: picture, name, facts and the before → after summary.
private struct VideoSummaryColumn: View {
    @Environment(AppModel.self) private var model
    let source: SourceItem
    let info: MediaInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                picture
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(source.name).font(.title3.weight(.semibold)).lineLimit(2).truncationMode(.middle)
                    Text(verbatim: model.presetName(for: source)).foregroundStyle(.secondary)
                }
                FlowTags(tags: RowFacts.tags(url: source.url, info: info) + [Format.duration(info.duration)])
                EstimateCard(estimate: model.sizeEstimate(for: source.id))
            }
            .padding(Spacing.l)
        }
        .background(.fill.quinary)
    }

    private var picture: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3B5765), Color(hex: 0x16232D)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image = source.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Radius.m))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

/// Tags that wrap onto the next line when the column is narrow.
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.xs) { ForEach(tags, id: \.self) { MetaTag(text: $0) } }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) { ForEach(tags.prefix(2), id: \.self) { MetaTag(text: $0) } }
                HStack(spacing: Spacing.xs) { ForEach(tags.dropFirst(2), id: \.self) { MetaTag(text: $0) } }
            }
        }
    }
}
