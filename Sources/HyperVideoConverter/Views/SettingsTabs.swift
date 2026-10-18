import HyperVideoCore
import SwiftUI

// MARK: Summary

struct SummaryTab: View {
    let info: MediaInfo
    @Binding var settings: EncodeSettings

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
                SettingRow(title: "Keep metadata", help: "Title, dates, location and other tags") {
                    Toggle("Keep metadata", isOn: $settings.keepMetadata).labelsHidden().toggleStyle(.switch)
                }
            }

            GlassSection(title: "Before → After", symbol: "arrow.right.circle") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    compareRow("Resolution", info.displaySize.map(Format.size) ?? "—", outputSize.map(Format.size) ?? "—")
                    compareRow("Video", info.videoCodec ?? "—", info.hasVideo ? settings.videoCodec.displayName : "—")
                    compareRow("Frame rate", info.frameRate.map(Format.fps) ?? "—", settings.frameRate.displayName)
                    compareRow("Audio", audioSource, audioOutput)
                    if !info.subtitleTracks.isEmpty {
                        compareRow("Subtitles", "\(info.subtitleTracks.count)", "\(keptSubtitles)")
                    }
                    compareRow("Duration", Format.duration(info.duration), Format.duration(outputDuration))
                    compareRow("Size", Format.bytes(info.fileBytes), estimatedSize)
                }
            }
        }
    }

    private var outputSize: CGSize? {
        guard let size = info.displaySize else { return nil }
        guard settings.videoCodec != .passthrough else { return size }
        return GeometryPlanner.plan(
            naturalSize: size, preferredTransform: .identity, crop: settings.crop, rotation: settings.rotation,
            flipHorizontal: settings.flipHorizontal, maxResolution: settings.maxResolution
        ).renderSize
    }

    private var outputDuration: Double {
        guard let trim = settings.trim else { return info.duration }
        return max(0, min(trim.end ?? info.duration, info.duration) - trim.start)
    }

    private var audioSource: String {
        guard let first = info.audioTracks.first else { return "None" }
        return "\(first.codec) \(first.channelDescription)" + (info.audioTracks.count > 1 ? " +\(info.audioTracks.count - 1)" : "")
    }

    private var keptSubtitles: Int {
        SubtitleTrackInfo.kept(info.subtitleTracks, kind: \.kind, selection: settings.subtitles,
                               container: settings.container).count
    }

    private var audioOutput: String {
        switch settings.audioCodec {
        case .none: "None"
        case .passthrough: "Passthrough"
        case .alac: "ALAC \(settings.audioMixdown.displayName)"
        case .aac: "AAC \(settings.audioMixdown.displayName) · \(settings.audioBitrateKbps) kbit/s"
        }
    }

    /// Only bitrate-driven encodes have a predictable size.
    private var estimatedSize: String {
        let audioTracks = settings.audioTracks == .all ? info.audioTracks.count : min(1, info.audioTracks.count)
        let audioKbps = settings.audioCodec == .aac ? settings.audioBitrateKbps * audioTracks : 0
        switch (settings.videoCodec, settings.rateControl) {
        case (.passthrough, _):
            return "≈ " + Format.bytes(Int64(Double(info.fileBytes) * outputDuration / max(info.duration, 0.001)))
        case (_, .averageBitrate(let kbps)) where settings.videoCodec.supportsRateControl:
            let bytes = Double(kbps + audioKbps) * 1_000 / 8 * outputDuration
            return "≈ " + Format.bytes(Int64(bytes))
        default:
            return "Depends on content"
        }
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
