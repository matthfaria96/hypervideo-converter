import HyperVideoCore
import SwiftUI

/// A second version of every kept track, e.g. AAC stereo next to surround passthrough.
struct ExtraVersionSection: View {
    @Binding var settings: EncodeSettings
    let bitrates: [Int]

    private static let fallback = AudioEncoding(codec: .aac, mixdown: .stereo, bitrateKbps: 160)

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.extraAudio != nil },
            set: { on in
                settings.extraAudio = on
                    ? AudioEncoding(codec: settings.audioCodec == .aac ? .passthrough : .aac, mixdown: .stereo, bitrateKbps: 160)
                    : nil
            }
        )
    }

    private var extra: Binding<AudioEncoding> {
        Binding(
            get: { settings.extraAudio ?? Self.fallback },
            set: { settings.extraAudio = $0 }
        )
    }

    var body: some View {
        SettingsSection(title: "Extra Version", symbol: "square.stack") {
            SettingRow(title: "Add a second version", help: "Each kept track is also written this way; players pick one") {
                Toggle("Add a second version", isOn: isOn).labelsHidden().toggleStyle(.switch)
            }
            if settings.extraAudio != nil {
                AudioEncodingFields(
                    encoding: extra,
                    codecs: AudioCodec.allCases.filter { $0 != .none },
                    bitrates: bitrates)
            }
        }
    }
}
