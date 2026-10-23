import HyperVideoCore
import SwiftUI

typealias SettingsEdit = @MainActor @Sendable ((inout EncodeSettings) -> Void) -> Void

/// The four quality profile cards; the chosen one is tinted with the accent.
struct ProfileCards: View {
    let selected: QualityProfile?
    let choose: @MainActor (QualityProfile) -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            ForEach(QualityProfile.allCases) { profile in
                card(profile, isSelected: profile == selected)
            }
        }
        .motion(value: selected)
    }

    private func card(_ profile: QualityProfile, isSelected: Bool) -> some View {
        ChoiceCard(symbol: profile.symbol,
                   title: String(localized: String.LocalizationValue(profile.name)),
                   tag: profile == .balanced ? StatusTag(text: String(localized: "Recommended"), tone: .accent) : nil,
                   summary: String(localized: String.LocalizationValue(profile.summary)),
                   isSelected: isSelected) { choose(profile) }
    }
}

/// Codec, maximum resolution and the quality slider.
struct VideoFields: View {
    let settings: EncodeSettings
    let edit: SettingsEdit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            FieldLabel(title: "Video Codec", symbol: "film")
            MenuField(label: "Video Codec", selection: settings.videoCodec, options: VideoCodec.allCases,
                      title: Self.title) { codec in edit { $0 = $0.choosing(codec: codec) } }
                .help("H.264 plays everywhere. HEVC (H.265) makes smaller files with the same look on recent devices.")

            FieldLabel(title: "Resolution", detail: "Optional", symbol: "aspectratio")
            MenuField(label: "Resolution", selection: settings.maxResolution, options: MaxResolution.allCases,
                      title: Self.title) { value in edit { $0.maxResolution = value } }
                .disabled(settings.videoCodec == .passthrough)
                .help("Videos larger than this are scaled down; smaller ones are never enlarged.")

            quality
        }
    }

    @ViewBuilder
    private var quality: some View {
        switch (settings.videoCodec.supportsRateControl, settings.rateControl) {
        case (true, .quality(let value)):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Compression Quality")
                        .help("Higher keeps more detail and makes a bigger file. The file size follows the content.")
                    Spacer()
                    Text(value, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Slider(value: Binding(get: { value }, set: { new in edit { $0.rateControl = .quality(new) } }), in: 0.2...1)
                HStack {
                    Text("Smaller file")
                    Spacer()
                    Text("More quality")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .motion(Motion.snappy, value: value)
        case (true, .averageBitrate(let kbps)):
            VStack(alignment: .leading, spacing: Spacing.s) {
                note("Fixed size: about \(Format.bitrate(Double(kbps) * 1_000)) of video, whatever the content.")
                Button("Use automatic quality instead") { edit { $0.rateControl = .quality(0.62) } }
                    .buttonStyle(.link)
                    .help("Lets the encoder pick the size that keeps the picture looking right")
            }
        default:
            note("This codec has a fixed quality, so there's nothing to tune.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func title(_ codec: VideoCodec) -> LocalizedStringKey {
        switch codec {
        case .h264: "H.264 — works almost everywhere"
        case .hevc: "HEVC / H.265 — smaller files"
        case .hevc10: "HEVC 10-bit — keeps HDR"
        case .proRes422: "Apple ProRes 422 — editing"
        case .proRes422HQ: "Apple ProRes 422 HQ — editing"
        case .proRes4444: "Apple ProRes 4444 — editing, alpha"
        case .proRes422LT: "Apple ProRes 422 LT — editing, lighter files"
        case .proRes422Proxy: "Apple ProRes 422 Proxy — offline editing"
        case .passthrough: "Passthrough — copy without re-encoding"
        }
    }

    static func title(_ resolution: MaxResolution) -> LocalizedStringKey {
        switch resolution {
        case .source: "Keep original resolution"
        case .uhd4320: "8K · 4320p"
        case .uhd2160: "4K · 2160p"
        case .qhd1440: "QHD · 1440p"
        case .fhd1080: "Full HD · 1080p"
        case .hd720: "HD · 720p"
        case .sd576: "SD · 576p"
        case .sd480: "SD · 480p"
        }
    }
}

/// Keep the original audio, remove metadata.
struct InspectorToggles: View {
    let settings: EncodeSettings
    let edit: SettingsEdit

    var body: some View {
        VStack(spacing: Spacing.m) {
            SwitchRow(title: "Keep original audio", detail: "Copies the audio tracks as they are whenever possible.",
                      isOn: settings.audioCodec == .passthrough) { on in
                edit { settings in
                    settings.audioCodec = on ? .passthrough : .aac
                    if on { settings.audioTracks = .all }
                    settings = settings.retuningAudioTracks()
                }
            }
            SwitchRow(title: "Remove metadata", detail: "Drops titles, dates, location and chapters from the file.",
                      isOn: !settings.keepMetadata) { on in edit { $0.keepMetadata = !on } }
        }
    }
}
