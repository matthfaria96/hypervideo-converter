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
    }

    private var rows: [Row] { info.subtitleTracks.map(Row.track) + files.map(Row.file) }

    private var kept: Set<String> {
        let tracks = SubtitleTrackInfo.kept(
            info.subtitleTracks.map(Row.track), kind: \.kind, selection: settings.subtitles, container: settings.container
        )
        let added = files.map(Row.file).filter { $0.kind.isSupported(in: settings.container) }
        return Set((tracks + added).map(\.id))
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

    private func rowView(_ row: Row, number: Int) -> some View {
        let included = kept.contains(row.id)
        return HStack {
            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(included ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text("Track \(number)").fontWeight(.medium)
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
