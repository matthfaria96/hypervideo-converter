import HyperVideoCore
import SwiftUI

let audioBitrateChoices = [64, 96, 128, 160, 192, 256, 320, 384, 448, 640]

/// The editable fields of one audio encoding: encoder, mixdown, sample rate, bitrate, gain and name.
struct AudioEncodingFields: View {
    @Binding var encoding: AudioEncoding
    /// Encoders offered; an empty list hides the encoder row.
    var codecs: [AudioCodec] = []
    var bitrates = audioBitrateChoices

    private var reencodes: Bool { encoding.codec != .passthrough && encoding.codec != .autoPassthru }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !codecs.isEmpty { codecRow }
            if reencodes && encoding.codec != .none {
                mixdownRow
                SettingRow(title: "Sample rate") {
                    Picker("Sample rate", selection: $encoding.sampleRate) {
                        ForEach(AudioSampleRate.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if encoding.codec == .aac || encoding.codec == .heAAC { bitrateRow }
                gainRow
            }
            SettingRow(title: "Name") {
                TextField("Name", text: nameBinding, prompt: Text("Automatic"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
        }
    }

    private var codecRow: some View {
        SettingRow(title: "Encoder") {
            Picker("Encoder", selection: $encoding.codec) {
                ForEach(codecs) { Text(localizing: $0.displayName).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var mixdownRow: some View {
        SettingRow(title: "Mixdown", help: "Falls back automatically if the source has fewer channels") {
            // No fixedSize around ViewThatFits: it would hide the available width and always
            // pick the wide segmented control, pushing the settings panel over the list.
            ViewThatFits(in: .horizontal) {
                mixdownPicker.pickerStyle(.segmented).fixedSize()
                mixdownPicker.pickerStyle(.menu).fixedSize()
            }
            .labelsHidden()
        }
    }

    private var mixdownPicker: some View {
        Picker("Mixdown", selection: $encoding.mixdown) {
            ForEach(AudioMixdown.allCases) { Text(localizing: $0.displayName).tag($0) }
        }
    }

    private var bitrateRow: some View {
        SettingRow(title: "Bitrate") {
            Picker("Bitrate", selection: $encoding.bitrateKbps) {
                ForEach(bitrates, id: \.self) { Text("\($0) kbit/s").tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var gainRow: some View {
        SettingRow(title: "Gain") {
            HStack {
                Slider(value: $encoding.gainDb, in: -20...20, step: 1).tint(Theme.accent).frame(width: 160)
                Text("\(encoding.gainDb, format: .number.sign(strategy: .always())) dB")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { encoding.trackName ?? "" },
            set: { encoding.trackName = $0.isEmpty ? nil : $0 }
        )
    }
}

/// One entry of the explicit audio track list.
struct AudioTrackCard: View {
    @Binding var setting: AudioTrackSetting
    let number: Int
    let sources: [AudioTrackInfo]
    let remove: () -> Void

    private static let encoders: [AudioCodec] = [.aac, .heAAC, .alac, .passthrough, .autoPassthru]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Track \(number)").fontWeight(.semibold)
                Spacer()
                Button("Remove Track", systemImage: "xmark", action: remove)
                    .labelStyle(.iconOnly)
                    .compatGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .help("Remove Track")
                    .accessibilityLabel("Remove Track")
            }
            .accessibilityElement(children: .combine)
            SettingRow(title: "Source") {
                Picker("Source", selection: $setting.sourceTrackID) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, track in
                        Text(verbatim: label(track, index: index)).tag(track.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            AudioEncodingFields(encoding: $setting.encoding, codecs: Self.encoders)
        }
        .padding(14)
        .card(.raised)
    }

    private func label(_ track: AudioTrackInfo, index: Int) -> String { Self.label(track, index: index) }

    /// "1 · eng · AAC Stereo", with the channel layout and a missing language localized.
    static func label(_ track: AudioTrackInfo, index: Int) -> String {
        let language = track.language ?? String(localized: "Unknown language")
        let channels = String(localized: String.LocalizationValue(track.channelDescription))
        return "\(index + 1) · \(language) · \(track.codec) \(channels)"
    }
}
