import HyperVideoCore
import SwiftUI

/// Subtitles tab: selection behavior, per-track rows and external files.
struct SubtitlesSettingsTab: View {
    @Environment(AppModel.self) private var model
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    let sourceID: UUID
    let files: [SubtitleFile]

    private var languages: Binding<String> {
        Binding(
            get: { LanguageList.format(settings.subtitleOptions.languages) },
            set: { settings.subtitleOptions.languages = LanguageList.parse($0) }
        )
    }

    private var burnInChoices: [(title: String, value: SubtitleBurnIn)] {
        let tracks = info.subtitleTracks.enumerated()
            .filter { $0.element.kind == .subtitle && $0.element.format == "Timed Text" }
            .map { (String(localized: "Track \($0.offset + 1)") + ($0.element.language.map { " (\($0))" } ?? ""),
                    SubtitleBurnIn.track(id: $0.element.id)) }
        let added = files.enumerated().map {
            (String(localized: "Track \(info.subtitleTracks.count + $0.offset + 1)") + ": \($0.element.name)",
             SubtitleBurnIn.file($0.element.url))
        }
        return tracks + added
    }

    var body: some View {
        VStack(spacing: 16) {
            behaviorSection
            tracksSection
            filesSection
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Selection Behavior", symbol: "captions.bubble") {
            SettingRow(title: "Tracks", help: "Copied as text, with their language; players show them on request") {
                Picker("Tracks", selection: $settings.subtitles) {
                    ForEach(SubtitleSelection.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Languages", help: "Empty keeps every language") {
                TextField("eng, por", text: languages).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            }
            SettingRow(title: "Burn In", help: "Draws one subtitle into the picture, so it always shows; needs video re-encoding") {
                Picker("Burn In", selection: $settings.burnIn) {
                    Text("None").tag(SubtitleBurnIn?.none)
                    ForEach(burnInChoices, id: \.title) { Text($0.title).tag(Optional($0.value)) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var tracksSection: some View {
        SettingsSection(title: "Tracks", symbol: "list.number") {
            if info.subtitleTracks.isEmpty && files.isEmpty {
                Text("No subtitle tracks yet. Add an SRT or WebVTT file, or name one like the video (e.g. Movie.pt-BR.srt) to pick it up automatically.")
                    .foregroundStyle(.secondary)
            }
            let list = settings.materializedSubtitleTracks(info: info)
            ForEach(Array(info.subtitleTracks.enumerated()), id: \.element.id) { index, track in
                SubtitleTrackRow(
                    track: track, number: index + 1,
                    setting: list.first { $0.sourceTrackID == track.id } ?? SubtitleTrackSetting(sourceTrackID: track.id),
                    settings: $settings, info: info)
            }
            Button("Reload from Behavior", systemImage: "arrow.counterclockwise") {
                settings = settings.resettingSubtitleTracks()
            }
            .buttonStyle(.subtle)
            .disabled(settings.subtitleOptions.tracks.isEmpty)
        }
    }

    private var filesSection: some View {
        SettingsSection(title: "External Files", symbol: "doc.text") {
            ForEach(files) { file in
                SubtitleFileRow(file: file, sourceID: sourceID, settings: $settings)
            }
            Button("Add Subtitle File…", systemImage: "plus") { model.chooseSubtitleFiles(for: sourceID) }
                .buttonStyle(.subtle)
        }
    }
}
