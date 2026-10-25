import AppKit
import HyperVideoCore
import SwiftUI
import UniformTypeIdentifiers

/// Chapter markers, editable titles and CSV import/export (CHP-01…03).
struct ChaptersSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @State private var problem: ChapterFileProblem?
    @Environment(\.editsAllVideos) private var editsAllVideos

    var body: some View {
        SettingsSection(title: "Chapters", symbol: "list.bullet.indent") {
            SettingRow(title: "Create chapter markers") {
                Toggle("Create chapter markers", isOn: markers).labelsHidden().toggleStyle(.switch)
            }
            if editsAllVideos {
                PerVideoHint(text: "Chapter names belong to one video. Select it in the list to rename its chapters.")
            } else if info.chapters.isEmpty {
                Text("This video has no chapters.").foregroundStyle(.secondary)
            } else {
                chapterGrid
                HStack(spacing: 8) {
                    Button("Import…") { importCSV() }
                    Button("Export…") { exportCSV() }
                    Spacer()
                }
                .compatGlassButtonStyle()
            }
        }
        .alert(Text(verbatim: problem?.title ?? ""),
               isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: problem?.message ?? "")
        }
    }

    private var markers: Binding<Bool> {
        Binding(
            get: { settings.chapterOptions.writesMarkers(keepMetadata: settings.keepMetadata) },
            set: { settings.chapterOptions.markers = $0 }
        )
    }

    private var chapterGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(info.chapters.enumerated()), id: \.offset) { index, chapter in
                GridRow {
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                    Text(Format.duration(chapter.start)).monospacedDigit()
                    Text(Format.duration(chapter.duration)).monospacedDigit().foregroundStyle(.secondary)
                    CommittingTextField(title: "Title", text: titleBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Chapter \(index + 1) title"))
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func titleBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { ChapterEditing.title(at: index, chapters: info.chapters, titles: settings.chapterOptions.titles) },
            set: {
                settings.chapterOptions = ChapterEditing.settingTitle(
                    $0, at: index, chapters: info.chapters, options: settings.chapterOptions
                )
            }
        )
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        PanelPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            let count = info.chapters.count
            let existing = settings.chapterOptions.titles
            Task {
                do {
                    settings.chapterOptions.titles = try await ChapterEditing.importTitles(
                        from: url, chapterCount: count, existing: existing
                    )
                } catch {
                    problem = .import(Self.message(for: error))
                }
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(info.url.deletingPathExtension().lastPathComponent) chapters.csv"
        let titles = ChapterEditing.effectiveTitles(chapters: info.chapters, titles: settings.chapterOptions.titles)
        PanelPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await ChapterEditing.exportCSV(titles: titles, to: url) } catch { problem = .export(Self.message(for: error)) }
            }
        }
    }

    /// The core library has no string tables, so chapter-file errors are localized here.
    static func message(for error: Error) -> String {
        switch error as? ChapterCSV.ParseError {
        case .invalidLine(let line): String(localized: "Line \(line) of the chapter file isn't “number,title”.")
        case .tooLarge: String(localized: "The chapter file is too large.")
        case nil: error.localizedDescription
        }
    }
}
