import HyperVideoCore
import SwiftUI

/// Text subtitles and closed captions are copied as-is, keeping their language tags.
struct SubtitlesTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    private var kept: Set<Int> {
        Set(SubtitleTrackInfo.kept(info.subtitleTracks, kind: \.kind, selection: settings.subtitles,
                                   container: settings.container).map(\.id))
    }

    var body: some View {
        VStack(spacing: 16) {
            GlassSection(title: "Subtitles", symbol: "captions.bubble") {
                SettingRow(title: "Tracks", help: "Copied without re-encoding, with their language") {
                    Picker("Tracks", selection: $settings.subtitles) {
                        ForEach(SubtitleSelection.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            GlassSection(title: "Source Tracks", symbol: "list.number") {
                if info.subtitleTracks.isEmpty {
                    Text("This source has no subtitle or caption tracks.").foregroundStyle(.secondary)
                }
                ForEach(Array(info.subtitleTracks.enumerated()), id: \.element.id) { index, track in
                    row(track, number: index + 1)
                }
            }
        }
    }

    private func row(_ track: SubtitleTrackInfo, number: Int) -> some View {
        let included = kept.contains(track.id)
        let supported = track.kind.isSupported(in: settings.container)
        return HStack {
            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(included ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text("Track \(number)").fontWeight(.medium)
            Text(track.kind == .closedCaption ? "\(track.format) captions" : track.format)
                .foregroundStyle(.secondary)
            if !supported {
                Text("Needs QuickTime (MOV)").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            if let language = track.language { InfoChip(symbol: "globe", text: language) }
        }
    }
}
