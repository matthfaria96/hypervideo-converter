import HyperVideoCore
import SwiftUI

/// Media facts of one video: streams, tracks, chapters and file details.
struct AnalyzeView: View {
    @Environment(AppModel.self) private var model

    private var source: SourceItem? { model.selectedSource ?? model.sources.first { model.selectedIDs.contains($0.id) } }

    var body: some View {
        PageScaffold(subtitle: "What's inside a video: streams, tracks, chapters and file details.") {
            if !model.sources.isEmpty { picker }
        } content: {
            if let source {
                SourceHeaderView(source: source, presetName: model.presetName(for: source),
                                 picture: model.ui.hero?.url == source.url ? model.ui.hero?.image : source.thumbnail)
                    .task(id: source.info?.duration) { await model.loadHero(for: source) }
                    .id(source.id)
                    .motionTransition(.content)
                if let info = source.info {
                    MediaFacts(info: info, url: source.url).motionTransition(.content)
                } else if let error = source.errorMessage {
                    StatusBanner(messages: [error])
                } else {
                    Label("Analyzing media…", systemImage: "rays").foregroundStyle(.secondary)
                }
            } else {
                EmptyPage(symbol: "magnifyingglass",
                          text: model.sources.isEmpty ? "Add a video to see what's inside it." : "Choose a video to analyze.")
            }
        }
        .motion(value: source?.id)
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
        VStack(spacing: Spacing.m) {
            if info.hasVideo {
                FactSection(title: "Video", symbol: "film") {
                    fact("Codec", info.videoCodec ?? "—")
                    fact("Resolution", info.displaySize.map(Format.size) ?? "—")
                    fact("Frame rate", info.frameRate.map(Format.fps) ?? "—")
                    fact("Bitrate", info.videoBitrate.map(Format.bitrate) ?? "—")
                    fact("Dynamic range", info.dynamicRange.rawValue)
                    fact("Scan", info.isInterlaced ? String(localized: "Interlaced") : String(localized: "Progressive"))
                }
            }
            FactSection(title: "Audio", symbol: "waveform") {
                if info.audioTracks.isEmpty { fact("Tracks", String(localized: "None")) }
                ForEach(Array(info.audioTracks.enumerated()), id: \.element.id) { index, track in
                    fact(String(localized: "Track \(index + 1)"),
                         [track.codec, String(localized: String.LocalizationValue(track.channelDescription)),
                          "\(Int(track.sampleRate / 1000)) kHz", track.language].compactMap { $0 }.joined(separator: " · "))
                }
            }
            if !info.subtitleTracks.isEmpty {
                FactSection(title: "Subtitles", symbol: "captions.bubble") {
                    ForEach(Array(info.subtitleTracks.enumerated()), id: \.element.id) { index, track in
                        fact(String(localized: "Track \(index + 1)"), [track.format, track.language].compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
            if !info.chapters.isEmpty {
                FactSection(title: "Chapters", symbol: "list.bullet.indent") {
                    ForEach(Array(info.chapters.enumerated()), id: \.offset) { index, chapter in
                        fact("\(index + 1). \(chapter.title)", Format.duration(chapter.start))
                    }
                }
            }
            FactSection(title: "File", symbol: "doc") {
                fact("Name", url.lastPathComponent)
                GridRow {
                    Text("Folder").foregroundStyle(.secondary)
                    Button {
                        SystemIntegration.reveal([url])
                    } label: {
                        Label(Format.path(url.deletingLastPathComponent()), systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .help("Show in Finder")
                }
                fact("Size", Format.bytes(info.fileBytes))
                fact("Duration", Format.duration(info.duration))
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}

private struct FactSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsSection(title: title, symbol: symbol) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) { content }
        }
    }
}
