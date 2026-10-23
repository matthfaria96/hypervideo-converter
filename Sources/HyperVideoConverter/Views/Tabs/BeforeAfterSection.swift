import HyperVideoCore
import SwiftUI

/// The Before → After grid on the Summary tab (SUM-07).
struct BeforeAfterSection: View {
    let info: MediaInfo
    let settings: EncodeSettings
    var subtitleFiles: [SubtitleFile] = []

    var body: some View {
        SettingsSection(title: "Before → After", symbol: "arrow.right.circle") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                compareRow("Resolution", info.displaySize.map(Format.size) ?? "—", outputSize.map(Format.size) ?? "—")
                compareRow("Video", info.videoCodec ?? "—", info.hasVideo ? Self.local(settings.videoCodec.displayName) : "—")
                compareRow("Frame rate", info.frameRate.map(Format.fps) ?? "—", Self.local(settings.frameRate.displayName))
                if info.hasVideo && settings.videoCodec != .passthrough {
                    compareRow("Filters", info.isInterlaced ? String(localized: "Interlaced") : "—", filterSummary)
                }
                compareRow("Audio", audioSource, audioOutput)
                if !info.subtitleTracks.isEmpty || !subtitleFiles.isEmpty {
                    compareRow("Subtitles", subtitleSource, "\(keptSubtitles)")
                }
                if !info.chapters.isEmpty {
                    compareRow("Chapters", "\(info.chapters.count)", "\(keptChapters.count)")
                }
                compareRow("Duration", Format.duration(info.duration), Format.duration(outputDuration))
                compareRow("Size", Format.bytes(info.fileBytes), estimatedSize)
            }
        }
    }

    private var outputStart: Double { settings.trim?.start ?? 0 }
    private var outputDuration: Double { settings.outputDuration(sourceDuration: info.duration) }

    /// Chapters as they will appear in the output: cut to the trim, dropped without markers.
    private var keptChapters: [Chapter] {
        guard settings.chapterOptions.writesMarkers(keepMetadata: settings.keepMetadata) else { return [] }
        return Chapter.clipped(info.chapters, start: outputStart, end: outputStart + outputDuration)
    }

    private var outputSize: CGSize? {
        guard let size = info.displaySize else { return nil }
        guard settings.videoCodec != .passthrough else { return size }
        let picture = settings.pictureOptions
        return GeometryPlanner.plan(
            naturalSize: size, preferredTransform: .identity,
            crop: picture.cropMode == .custom ? settings.crop : .zero,
            rotation: settings.rotation, flipHorizontal: settings.flipHorizontal,
            maxResolution: settings.maxResolution, picture: picture
        ).renderSize
    }

    private var audioSource: String {
        guard let first = info.audioTracks.first else { return String(localized: "None") }
        return "\(first.codec) \(Self.local(first.channelDescription))" + (info.audioTracks.count > 1 ? " +\(info.audioTracks.count - 1)" : "")
    }

    private var filterSummary: String {
        let filters = settings.filters
        let names = [
            filters.deinterlaces(sourceIsInterlaced: info.isInterlaced) ? String(localized: "Deinterlace") : nil,
            filters.denoise != .off ? String(localized: "Denoise") + " (\(Self.local(filters.denoise.displayName)))" : nil,
            filters.chromaSmooth != .off ? String(localized: "Chroma Smooth") : nil,
            filters.sharpen != .off ? String(localized: "Sharpen") + " (\(Self.local(filters.sharpen.displayName)))" : nil,
            filters.colorspace != .off ? Self.local(filters.colorspace.displayName) : nil,
            filters.grayscale ? String(localized: "Grayscale") : nil
        ].compactMap { $0 }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var subtitleSource: String {
        subtitleFiles.isEmpty ? "\(info.subtitleTracks.count)" : String(localized: "\(info.subtitleTracks.count) + \(subtitleFiles.count) files")
    }

    private var keptSubtitles: Int {
        let tracks = SubtitleTrackInfo.kept(
            info.subtitleTracks.map(\.kind), kind: { $0 }, selection: settings.subtitles, container: settings.container
        )
        let added = SubtitleTrackInfo.Kind.subtitle.isSupported(in: settings.container) ? subtitleFiles.count : 0
        return tracks.count + added
    }

    private var audioOutput: String {
        guard let extra = settings.extraAudio, settings.audioCodec != .none else { return mainAudioOutput }
        return mainAudioOutput + " + " + (extra.codec == .aac ? "AAC \(Self.local(extra.mixdown.displayName))" : Self.local(extra.codec.displayName))
    }

    private var mainAudioOutput: String {
        let tracks = settings.audioOptions.tracks
        if tracks.count > 1 { return String(localized: "\(tracks.count) tracks") }
        switch settings.audioCodec {
        case .none: return String(localized: "None")
        case .passthrough: return String(localized: "Passthrough")
        case .autoPassthru: return String(localized: "Auto Passthru")
        case .heAAC: return "HE-AAC \(Self.local(settings.audioMixdown.displayName)) · \(settings.audioBitrateKbps) kbit/s"
        case .alac: return "ALAC \(Self.local(settings.audioMixdown.displayName))"
        case .aac: return "AAC \(Self.local(settings.audioMixdown.displayName)) · \(settings.audioBitrateKbps) kbit/s"
        }
    }

    /// The same prediction as the inspector's estimate card.
    private var estimatedSize: String {
        OutputEstimate.prediction(info: info, settings: settings)
            .map { SizeEstimate.label(bytes: $0.bytes, kind: $0.kind) } ?? String(localized: "Depends on content")
    }

    static func local(_ text: String) -> String { String(localized: String.LocalizationValue(text)) }

    private func compareRow(_ title: LocalizedStringKey, _ before: String, _ after: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(before).monospacedDigit()
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            Text(after).monospacedDigit().fontWeight(before == after ? .regular : .semibold)
        }
    }
}
