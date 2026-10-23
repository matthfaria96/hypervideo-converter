import AppKit
import HyperVideoCore
import SwiftUI
import UniformTypeIdentifiers

/// Chapter markers, editable titles and CSV import/export (CHP-01…03).
struct ChaptersSettingsTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    @State private var importError: String?

    var body: some View {
        SettingsSection(title: "Chapters", symbol: "list.bullet.indent") {
            SettingRow(title: "Create chapter markers") {
                Toggle("Create chapter markers", isOn: markers).labelsHidden().toggleStyle(.switch)
            }
            if info.chapters.isEmpty {
                Text("This video has no chapters.").foregroundStyle(Theme.muted)
            } else {
                chapterGrid
                HStack(spacing: 8) {
                    Button("Import…") { importCSV() }
                    Button("Export…") { exportCSV() }
                    Spacer()
                }
                .buttonStyle(.subtle)
            }
        }
        .alert("Chapters not imported", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
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
                    Text("\(index + 1)").monospacedDigit().foregroundStyle(Theme.muted)
                    Text(Format.duration(chapter.start)).monospacedDigit()
                    Text(Format.duration(chapter.duration)).monospacedDigit().foregroundStyle(Theme.muted)
                    TextField("Title", text: titleBinding(index)).textFieldStyle(.roundedBorder)
                }
                .accessibilityElement(children: .combine)
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
                    importError = Self.message(for: error)
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
                do { try await ChapterEditing.exportCSV(titles: titles, to: url) } catch { importError = Self.message(for: error) }
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
