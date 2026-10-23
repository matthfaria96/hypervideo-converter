import HyperVideoCore
import SwiftUI

typealias SettingsEdit = @MainActor @Sendable ((inout EncodeSettings) -> Void) -> Void

/// The four quality profile cards; the chosen one has an amber border.
struct ProfileCards: View {
    let selected: QualityProfile?
    let choose: @MainActor (QualityProfile) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(QualityProfile.allCases) { profile in
                card(profile, isSelected: profile == selected)
            }
        }
    }

    private func card(_ profile: QualityProfile, isSelected: Bool) -> some View {
        Button {
            choose(profile)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.accentLight : Color(hex: 0xDDDDDD))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color(hex: 0x594421) : Color(hex: 0x39393F), in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(localizing: profile.name).font(.system(size: 11, weight: .semibold))
                        if profile == .balanced {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.accentLight)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accentWash, in: .capsule)
                        }
                    }
                    Text(localizing: profile.summary).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Circle()
                    .strokeBorder(isSelected ? Theme.accent : Color(hex: 0x777777), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .overlay { if isSelected { Circle().fill(Theme.accent).frame(width: 6, height: 6) } }
            }
            .padding(10)
            .card(fill: isSelected ? Theme.selectedCard : Color(hex: 0x27272B), radius: 9,
                  stroke: isSelected ? Color(hex: 0xD9A33A) : Theme.line)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Text(localizing: profile.name)), \(Text(localizing: profile.summary))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Codec, maximum resolution and the quality slider.
struct VideoFields: View {
    let settings: EncodeSettings
    let edit: SettingsEdit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(title: "Video Codec")
            MenuField(label: "Video Codec", selection: settings.videoCodec, options: VideoCodec.allCases,
                      title: Self.title) { codec in edit { $0 = $0.choosing(codec: codec) } }
                .help("H.264 plays everywhere. HEVC (H.265) makes smaller files with the same look on recent devices.")
                .padding(.bottom, 17)

            FieldLabel(title: "Resolution", detail: "Optional")
            MenuField(label: "Resolution", selection: settings.maxResolution, options: MaxResolution.allCases,
                      title: Self.title) { value in edit { $0.maxResolution = value } }
                .disabled(settings.videoCodec == .passthrough)
                .help("Videos larger than this are scaled down; smaller ones are never enlarged.")
                .padding(.bottom, 17)

            quality
        }
    }

    @ViewBuilder
    private var quality: some View {
        switch (settings.videoCodec.supportsRateControl, settings.rateControl) {
        case (true, .quality(let value)):
            HStack {
                Text("Compression Quality").font(.system(size: 11, weight: .semibold))
                    .help("Higher keeps more detail and makes a bigger file. The file size follows the content.")
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: { new in edit { $0.rateControl = .quality(new) } }), in: 0.2...1)
                .tint(Theme.accent)
                .controlSize(.small)
                .padding(.vertical, 4)
            HStack {
                Text("Smaller file")
                Spacer()
                Text("More quality")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted)
        case (true, .averageBitrate(let kbps)):
            VStack(alignment: .leading, spacing: 6) {
                note("Fixed size: about \(Format.bitrate(Double(kbps) * 1_000)) of video, whatever the content.")
                Button("Use automatic quality instead") { edit { $0.rateControl = .quality(0.62) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accentLight)
                    .frame(minHeight: 28)
                    .help("Lets the encoder pick the size that keeps the picture looking right")
            }
        default:
            note("This codec has a fixed quality, so there's nothing to tune.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Theme.muted)
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
        VStack(spacing: 13) {
            row("Keep original audio", "Copies the audio tracks as they are whenever possible.",
                isOn: settings.audioCodec == .passthrough) { on in
                edit { settings in
                    settings.audioCodec = on ? .passthrough : .aac
                    if on { settings.audioTracks = .all }
                }
            }
            row("Remove metadata", "Drops titles, dates, location and chapters from the file.",
                isOn: !settings.keepMetadata) { on in edit { $0.keepMetadata = !on } }
        }
    }

    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, isOn: Bool,
                     set: @escaping @MainActor @Sendable (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(PillSwitchStyle())
    }
}
