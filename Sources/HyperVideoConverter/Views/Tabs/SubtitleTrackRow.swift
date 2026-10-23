import HyperVideoCore
import SwiftUI

/// A radio-style button used for the one-at-a-time Default and Burn choices.
struct RadioToggle: View {
    let isOn: Bool
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One source subtitle track with its include, default, forced-only, burn and name controls.
struct SubtitleTrackRow: View {
    let track: SubtitleTrackInfo
    let number: Int
    let setting: SubtitleTrackSetting
    @Binding var settings: EncodeSettings
    let info: MediaInfo

    private var canBurn: Bool { track.kind == .subtitle && track.format == "Timed Text" }
    private var isBurned: Bool { settings.burnIn == .track(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 14) {
                Toggle("Include", isOn: edit(\.include)).toggleStyle(.checkbox)
                RadioToggle(isOn: setting.isDefault, title: "Default", help: "Default track") {
                    update { $0.isDefault.toggle() }
                }
                if canBurn {
                    RadioToggle(isOn: isBurned, title: "Burn", help: "Draws this track into the picture") {
                        settings.burnIn = isBurned ? nil : .track(id: track.id)
                    }
                }
            }
            .controlSize(.small)
            HStack(spacing: 12) {
                Toggle("Forced only", isOn: edit(\.forcedOnly))
                    .toggleStyle(.checkbox)
                    .help("Keeps the track only if it holds forced subtitles")
                    .fixedSize()
                TextField("Name", text: nameBinding, prompt: Text(verbatim: track.name ?? ""))
                    .textFieldStyle(.roundedBorder)
            }
            .controlSize(.small)
        }
        .padding(12)
        .card(fill: Theme.panelRaised, radius: 10)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Text("Track \(number)").fontWeight(.medium)
            Text(verbatim: track.kind == .closedCaption ? String(localized: "\(track.format) captions") : track.format)
                .foregroundStyle(.secondary)
            if track.isForcedOnly { InfoChip(symbol: "flag", text: String(localized: "Forced")) }
            if isBurned { InfoChip(symbol: "flame", text: String(localized: "Burned in")) }
            if !track.kind.isSupported(in: settings.container) {
                Text("Needs QuickTime (MOV)").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            if let language = track.language { InfoChip(symbol: "globe", text: language) }
        }
    }

    private func update(_ change: (inout SubtitleTrackSetting) -> Void) {
        settings = settings.updatingSubtitleTrack(track.id, info: info, change)
    }

    private func edit(_ keyPath: WritableKeyPath<SubtitleTrackSetting, Bool>) -> Binding<Bool> {
        Binding(get: { setting[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { setting.name ?? "" },
            set: { value in update { $0.name = value.isEmpty ? nil : value } }
        )
    }
}
