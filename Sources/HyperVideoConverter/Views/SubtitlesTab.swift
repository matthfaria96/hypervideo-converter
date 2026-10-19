import HyperVideoCore
import SwiftUI

/// Text subtitles, closed captions and external SRT/WebVTT files are copied as
/// text tracks with their language tags.
struct SubtitlesTab: View {
    @Environment(AppModel.self) private var model
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    let sourceID: UUID
    let files: [SubtitleFile]

    /// A row per track, source tracks first, as the encoder orders them.
    private enum Row: Identifiable {
        case track(SubtitleTrackInfo)
        case file(SubtitleFile)

        var id: String {
            switch self {
            case .track(let track): "track-\(track.id)"
            case .file(let file): "file-\(file.url.path)"
            }
        }

        var kind: SubtitleTrackInfo.Kind {
            if case .track(let track) = self { return track.kind }
            return .subtitle
        }

        var burnIn: SubtitleBurnIn {
            switch self {
            case .track(let track): .track(id: track.id)
            case .file(let file): .file(file.url)
            }
        }

        /// External files and source Timed Text tracks can be drawn into the picture.
        var canBurnIn: Bool {
            switch self {
            case .track(let track): track.kind == .subtitle && track.format == "Timed Text"
            case .file: true
            }
        }
    }

    private var rows: [Row] { info.subtitleTracks.map(Row.track) + files.map(Row.file) }

    private var kept: Set<String> {
        let tracks = SubtitleTrackInfo.kept(
            info.subtitleTracks.map(Row.track), kind: \.kind, selection: settings.subtitles, container: settings.container
        )
        let added = files.map(Row.file).filter { $0.kind.isSupported(in: settings.container) }
        return Set((tracks + added).filter { $0.burnIn != settings.burnIn }.map(\.id))
    }

    private var burnInRows: [(number: Int, row: Row)] {
        rows.enumerated().filter { $0.element.canBurnIn }.map { ($0.offset + 1, $0.element) }
    }

    var body: some View {
        VStack(spacing: 16) {
            GlassSection(title: "Subtitles", symbol: "captions.bubble") {
                SettingRow(title: "Tracks", help: "Copied as text, with their language; players show them on request") {
                    Picker("Tracks", selection: $settings.subtitles) {
                        ForEach(SubtitleSelection.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(title: "Burn In", help: "Draws one subtitle into the picture, so it always shows; needs video re-encoding") {
                    Picker("Burn In", selection: $settings.burnIn) {
                        Text("None").tag(SubtitleBurnIn?.none)
                        ForEach(burnInRows, id: \.row.id) { item in
                            Text(burnInTitle(item.row, number: item.number)).tag(Optional(item.row.burnIn))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            GlassSection(title: "Tracks", symbol: "list.number") {
                if rows.isEmpty {
                    Text("No subtitle tracks yet. Add an SRT or WebVTT file, or name one like the video (e.g. Movie.pt-BR.srt) to pick it up automatically.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, number: index + 1)
                }
                Button("Add Subtitle File…", systemImage: "plus") { model.chooseSubtitleFiles(for: sourceID) }
                    .buttonStyle(.glass)
            }
        }
    }

    private func burnInTitle(_ row: Row, number: Int) -> String {
        switch row {
        case .track(let track): "Track \(number)" + (track.language.map { " (\($0))" } ?? "")
        case .file(let file): "Track \(number): \(file.name)"
        }
    }

    private func rowView(_ row: Row, number: Int) -> some View {
        let included = kept.contains(row.id)
        return HStack {
            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(included ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text("Track \(number)").fontWeight(.medium)
            if row.burnIn == settings.burnIn {
                InfoChip(symbol: "flame", text: "Burned in")
            }
            switch row {
            case .track(let track):
                Text(track.kind == .closedCaption ? "\(track.format) captions" : track.format).foregroundStyle(.secondary)
                if !track.kind.isSupported(in: settings.container) {
                    Text("Needs QuickTime (MOV)").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if let language = track.language { InfoChip(symbol: "globe", text: language) }
            case .file(let file):
                Label(file.name, systemImage: "doc.text").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                InfoChip(symbol: "globe", text: file.language ?? "Unknown")
                Button("Remove", systemImage: "xmark") { model.removeSubtitleFile(file, from: sourceID) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        }
    }
}
