import HyperVideoCore
import SwiftUI

/// Inline Summary: output, before → after, trim and chapter range. Quality comes from
/// the panel's Preset picker.
struct SummarySettingsTab: View {
    let info: MediaInfo
    /// The video shown; nil when the tabs edit every video.
    let sourceID: UUID?
    @Binding var settings: EncodeSettings
    var subtitleFiles: [SubtitleFile] = []
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            outputSection
            BeforeAfterSection(info: info, settings: settings, subtitleFiles: subtitleFiles)
            TrimTab(info: info, settings: $settings)
            if info.chapters.count > 1 { rangeSection }
        }
    }

    private var outputSection: some View {
        SettingsSection(title: "Output", symbol: "shippingbox") {
            SettingRow(title: "Format") {
                Picker("Format", selection: $settings.container) {
                    ForEach(ContainerFormat.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Web optimized", help: "Moves the index to the start for fast streaming") {
                Toggle("Web optimized", isOn: $settings.optimizeForWeb).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Align A/V start", help: "Starts every track at the first video frame") {
                Toggle("Align A/V start", isOn: $settings.alignAVStart).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Passthru common metadata", help: "Keeps titles, dates and other tags from the source") {
                Toggle("Passthru common metadata", isOn: $settings.keepMetadata).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var rangeIndices: (from: Int, through: Int)? {
        ChapterEditing.rangeIndices(trim: settings.trim, chapters: info.chapters)
    }

    private var rangeSection: some View {
        SettingsSection(title: "Range", symbol: "list.bullet.indent") {
            SettingRow(title: "From chapter") {
                chapterMenu(selection: rangeIndices?.from) { applyRange(from: $0, through: max($0, rangeIndices?.through ?? $0)) }
            }
            SettingRow(title: "To chapter") {
                chapterMenu(selection: rangeIndices?.through) { applyRange(from: min($0, rangeIndices?.from ?? $0), through: $0) }
            }
        }
    }

    private func chapterMenu(selection: Int?, choose: @escaping (Int) -> Void) -> some View {
        Picker("Chapter", selection: Binding<Int>(get: { selection ?? -1 }, set: { if $0 >= 0 { choose($0) } })) {
            if selection == nil { Text("Custom").tag(-1) }
            ForEach(info.chapters.indices, id: \.self) { index in
                Text("\(index + 1). \(ChapterEditing.title(at: index, chapters: info.chapters, titles: settings.chapterOptions.titles))")
                    .tag(index)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func applyRange(from: Int, through: Int) {
        guard let trim = TrimRange.chapters(info.chapters, from: from, through: through) else { return }
        let whole = from == 0 && through == info.chapters.count - 1
        settings.trim = whole ? nil : trim
    }
}
