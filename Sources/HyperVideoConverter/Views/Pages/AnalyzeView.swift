import HyperVideoCore
import SwiftUI

/// Media facts of one video: streams, tracks, chapters and file details.
struct AnalyzeView: View {
    @Environment(AppModel.self) private var model

    private var source: SourceItem? { model.selectedSource ?? model.sources.first { model.selectedIDs.contains($0.id) } }

    var body: some View {
        PageScaffold(eyebrow: "Tools", title: "Analyze Video",
                     subtitle: "What's inside a video: streams, tracks, chapters and file details.") {
            if !model.sources.isEmpty { picker }
        } content: {
            if let source {
                SourceHeaderView(source: source, presetName: model.presetName(for: source))
                if let info = source.info {
                    MediaFacts(info: info, url: source.url)
                } else if let error = source.errorMessage {
                    StatusBanner(messages: [error])
                } else {
                    Label("Analyzing media…", systemImage: "rays").foregroundStyle(Theme.muted)
                }
            } else {
                EmptyPage(symbol: "magnifyingglass",
                          text: model.sources.isEmpty ? "Add a video to see what's inside it." : "Choose a video to analyze.")
            }
        }
    }

    private var picker: some View {
        Picker("Video", selection: Binding(get: { source?.id }, set: { id in model.selectedIDs = id.map { [$0] } ?? [] })) {
            if source == nil { Text("Choose a video").tag(UUID?.none) }
            ForEach(model.sources) { Text(verbatim: $0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .frame(maxWidth: 260)
    }
}

private struct MediaFacts: View {
    let info: MediaInfo
    let url: URL

    var body: some View {
        VStack(spacing: 14) {
            if info.hasVideo {
                FactSection(title: "Video") {
                    fact("Codec", info.videoCodec ?? "—")
                    fact("Resolution", info.displaySize.map(Format.size) ?? "—")
                    fact("Frame rate", info.frameRate.map(Format.fps) ?? "—")
                    fact("Bitrate", info.videoBitrate.map(Format.bitrate) ?? "—")
                    fact("Dynamic range", info.dynamicRange.rawValue)
                    fact("Scan", info.isInterlaced ? String(localized: "Interlaced") : String(localized: "Progressive"))
                }
            }
            FactSection(title: "Audio") {
                if info.audioTracks.isEmpty { fact("Tracks", String(localized: "None")) }
                ForEach(Array(info.audioTracks.enumerated()), id: \.element.id) { index, track in
                    fact(String(localized: "Track \(index + 1)"),
                         [track.codec, String(localized: String.LocalizationValue(track.channelDescription)),
                          "\(Int(track.sampleRate / 1000)) kHz", track.language].compactMap { $0 }.joined(separator: " · "))
                }
            }
            if !info.subtitleTracks.isEmpty {
                FactSection(title: "Subtitles") {
                    ForEach(Array(info.subtitleTracks.enumerated()), id: \.element.id) { index, track in
                        fact(String(localized: "Track \(index + 1)"), [track.format, track.language].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
            if !info.chapters.isEmpty {
                FactSection(title: "Chapters") {
                    ForEach(Array(info.chapters.enumerated()), id: \.offset) { index, chapter in
                        fact("\(index + 1). \(chapter.title)", Format.duration(chapter.start))
                    }
                }
            }
            FactSection(title: "File") {
                fact("Name", url.lastPathComponent)
                fact("Folder", (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                fact("Size", Format.bytes(info.fileBytes))
                fact("Duration", Format.duration(info.duration))
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(LocalizedStringKey(title)).foregroundStyle(Theme.muted)
            Text(verbatim: value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
        .font(.system(size: 12))
    }
}

private struct FactSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) { content }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Color(hex: 0x202023))
    }
}
