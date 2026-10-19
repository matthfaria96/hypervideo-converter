import HyperVideoCore
import SwiftUI

// MARK: Summary

struct SummaryTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings
    var subtitleFiles: [SubtitleFile] = []

    var body: some View {
        VStack(spacing: 16) {
            GlassSection(title: "Output", symbol: "shippingbox") {
                SettingRow(title: "Format") {
                    Picker("Format", selection: $settings.container) {
                        ForEach(ContainerFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(title: "Web optimized", help: "Moves the index to the start for fast streaming") {
                    Toggle("Web optimized", isOn: $settings.optimizeForWeb).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Keep metadata", help: "Title, dates, location, chapters and other tags") {
                    Toggle("Keep metadata", isOn: $settings.keepMetadata).labelsHidden().toggleStyle(.switch)
                }
            }

            GlassSection(title: "Before → After", symbol: "arrow.right.circle") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    compareRow("Resolution", info.displaySize.map(Format.size) ?? "—", outputSize.map(Format.size) ?? "—")
                    compareRow("Video", info.videoCodec ?? "—", info.hasVideo ? settings.videoCodec.displayName : "—")
                    compareRow("Frame rate", info.frameRate.map(Format.fps) ?? "—", settings.frameRate.displayName)
                    if info.hasVideo && settings.videoCodec != .passthrough {
                        compareRow("Filters", info.isInterlaced ? "Interlaced" : "—", filterSummary)
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

            if !keptChapters.isEmpty {
                GlassSection(title: "Chapters", symbol: "list.bullet.indent") {
                    ForEach(Array(keptChapters.enumerated()), id: \.offset) { index, chapter in
                        HStack {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.tertiary).frame(width: 24, alignment: .trailing)
                            Text(chapter.title).lineLimit(1)
                            Spacer()
                            Text(Format.duration(chapter.start - outputStart)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var outputStart: Double { settings.trim?.start ?? 0 }

    /// Chapters as they will appear in the output: cut to the trim, dropped without metadata.
    private var keptChapters: [Chapter] {
        guard settings.keepMetadata else { return [] }
        return Chapter.clipped(info.chapters, start: outputStart, end: outputStart + outputDuration)
    }

    private var outputSize: CGSize? {
        guard let size = info.displaySize else { return nil }
        guard settings.videoCodec != .passthrough else { return size }
        return GeometryPlanner.plan(
            naturalSize: size, preferredTransform: .identity, crop: settings.crop, rotation: settings.rotation,
            flipHorizontal: settings.flipHorizontal, maxResolution: settings.maxResolution
        ).renderSize
    }

    private var outputDuration: Double { settings.outputDuration(sourceDuration: info.duration) }

    private var audioSource: String {
        guard let first = info.audioTracks.first else { return "None" }
        return "\(first.codec) \(first.channelDescription)" + (info.audioTracks.count > 1 ? " +\(info.audioTracks.count - 1)" : "")
    }

    private var filterSummary: String {
        let filters = settings.filters
        let names = [
            filters.deinterlaces(sourceIsInterlaced: info.isInterlaced) ? "Deinterlace" : nil,
            filters.denoise != .off ? "Denoise \(filters.denoise.displayName.lowercased())" : nil,
            filters.sharpen != .off ? "Sharpen \(filters.sharpen.displayName.lowercased())" : nil,
            filters.grayscale ? "Grayscale" : nil
        ].compactMap { $0 }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var subtitleSource: String {
        subtitleFiles.isEmpty ? "\(info.subtitleTracks.count)" : "\(info.subtitleTracks.count) + \(subtitleFiles.count) files"
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
        return mainAudioOutput + " + " + (extra.codec == .aac ? "AAC \(extra.mixdown.displayName)" : extra.codec.displayName)
    }

    private var mainAudioOutput: String {
        switch settings.audioCodec {
        case .none: "None"
        case .passthrough: "Passthrough"
        case .alac: "ALAC \(settings.audioMixdown.displayName)"
        case .aac: "AAC \(settings.audioMixdown.displayName) · \(settings.audioBitrateKbps) kbit/s"
        }
    }

    /// Only bitrate-driven and passthrough encodes have a predictable size.
    private var estimatedSize: String {
        OutputEstimate.bytes(info: info, settings: settings).map { "≈ " + Format.bytes($0) } ?? "Depends on content"
    }

    private func compareRow(_ title: String, _ before: String, _ after: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(before).monospacedDigit()
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            Text(after).monospacedDigit().fontWeight(before == after ? .regular : .semibold)
        }
    }
}

// MARK: Video

struct VideoTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

    var body: some View {
        VStack(spacing: 16) {
            GlassSection(title: "Encoder", symbol: "cpu") {
                SettingRow(title: "Codec") {
                    Picker("Codec", selection: $settings.videoCodec) {
                        ForEach(VideoCodec.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if info.dynamicRange != .sdr && !settings.videoCodec.isTenBit && settings.videoCodec != .passthrough {
                    Label("This \(info.dynamicRange.rawValue) source will be converted to SDR. Choose HEVC 10-bit or ProRes to keep HDR.",
                          systemImage: "sun.max.trianglebadge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                SettingRow(title: "Frame rate") {
                    Picker("Frame rate", selection: $settings.frameRate) {
                        ForEach(FrameRate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if settings.videoCodec != .passthrough {
                FiltersSection(info: info, filters: $settings.filters)
            }

            if settings.videoCodec.supportsRateControl {
                RateControlSection(settings: $settings)
                GlassSection(title: "Advanced", symbol: "slider.horizontal.3") {
                    SettingRow(title: "Prioritize speed", help: "Faster encodes at slightly lower efficiency") {
                        Toggle("Prioritize speed", isOn: $settings.prioritizeSpeed).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "B-frames", help: "Better compression; disable for some editors") {
                        Toggle("B-frames", isOn: $settings.allowBFrames).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Keyframe interval") {
                        Stepper(value: $settings.keyframeIntervalSeconds, in: 0.5...10, step: 0.5) {
                            Text("\(settings.keyframeIntervalSeconds.formatted()) s").monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

private struct FiltersSection: View {
    let info: MediaInfo
    @Binding var filters: VideoFilters

    var body: some View {
        GlassSection(title: "Filters", symbol: "camera.filters") {
            SettingRow(title: "Deinterlace", help: info.isInterlaced ? "This source is interlaced" : "Automatic acts only on interlaced sources") {
                Picker("Deinterlace", selection: $filters.deinterlace) {
                    ForEach(DeinterlaceMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            strengthRow("Denoise", help: "Smooths grain and compression noise", selection: $filters.denoise)
            strengthRow("Sharpen", help: "Crisper edges; best kept light", selection: $filters.sharpen)
            SettingRow(title: "Grayscale") {
                Toggle("Grayscale", isOn: $filters.grayscale).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private func strengthRow(_ title: String, help: String, selection: Binding<FilterStrength>) -> some View {
        SettingRow(title: title, help: help) {
            Picker(title, selection: selection) {
                ForEach(FilterStrength.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

private struct RateControlSection: View {
    @Binding var settings: EncodeSettings

    private var isQuality: Binding<Bool> {
        Binding(
            get: { if case .quality = settings.rateControl { true } else { false } },
            set: { settings.rateControl = $0 ? .quality(0.62) : .averageBitrate(6_000) }
        )
    }

    private var quality: Binding<Double> {
        Binding(
            get: { if case .quality(let q) = settings.rateControl { q } else { 0.62 } },
            set: { settings.rateControl = .quality($0) }
        )
    }

    private var bitrate: Binding<Int> {
        Binding(
            get: { if case .averageBitrate(let kbps) = settings.rateControl { kbps } else { 6_000 } },
            set: { settings.rateControl = .averageBitrate(max(100, $0)) }
        )
    }

    var body: some View {
        GlassSection(title: "Quality", symbol: "dial.medium") {
            Picker("Mode", selection: isQuality) {
                Text("Constant Quality").tag(true)
                Text("Average Bitrate").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if isQuality.wrappedValue {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Self.describe(quality.wrappedValue)).fontWeight(.semibold)
                        Spacer()
                        Text("\(Int(quality.wrappedValue * 100))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: quality, in: 0.2...1) {
                        Text("Quality")
                    } minimumValueLabel: {
                        Text("Smaller").font(.caption)
                    } maximumValueLabel: {
                        Text("Better").font(.caption)
                    }
                    .labelsHidden()
                }
            } else {
                SettingRow(title: "Average bitrate") {
                    HStack {
                        TextField("kbit/s", value: bitrate, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                        Text("kbit/s").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func describe(_ quality: Double) -> String {
        switch quality {
        case ..<0.4: "Compact"
        case ..<0.58: "Balanced"
        case ..<0.75: "High Quality"
        case ..<0.9: "Very High Quality"
        default: "Near Lossless"
        }
    }
}
