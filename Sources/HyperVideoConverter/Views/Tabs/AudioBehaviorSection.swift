import HyperVideoCore
import SwiftUI

/// Which source tracks are kept, languages, Auto Passthru rules and naming.
struct AudioBehaviorSection: View {
    @Binding var settings: EncodeSettings

    private let fallbacks: [AudioCodec] = [.aac, .heAAC, .alac]

    var body: some View {
        SettingsSection(title: "Selection Behavior", symbol: "line.3.horizontal.decrease.circle") {
            SettingRow(title: "Tracks") {
                Picker("Tracks", selection: $settings.audioTracks) {
                    ForEach(AudioTrackSelection.allCases) { Text(localizing: $0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Languages", help: "Empty keeps every language") {
                CommittingTextField(title: "eng, por", text: languages)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            SettingRow(title: "Auto Passthru", help: "Copied as is when the source uses them") {
                // Three fixed columns: wide enough for "DTS-HD", narrow enough to never
                // widen the inspector (the row stacks the label above when needed).
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), alignment: .leading), count: 3),
                          alignment: .leading, spacing: Spacing.xs + 2) {
                    ForEach(PassthruCodec.allCases) { codec in
                        Toggle(codec.displayName, isOn: allowed(codec))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .fixedSize()
            }
            SettingRow(title: "Passthru fallback") {
                Picker("Passthru fallback", selection: $settings.audioOptions.fallback) {
                    ForEach(fallbacks) { Text(localizing: $0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(title: "Only first track gets the extra version") {
                Toggle("Only first track gets the extra version", isOn: $settings.audioOptions.extraFirstTrackOnly)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingRow(title: "Name tracks automatically") {
                Toggle("Name tracks automatically", isOn: $settings.audioOptions.automaticNaming)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var languages: Binding<String> {
        Binding(
            get: { LanguageList.format(settings.audioOptions.languages) },
            set: { settings.audioOptions.languages = LanguageList.parse($0) }
        )
    }

    private func allowed(_ codec: PassthruCodec) -> Binding<Bool> {
        Binding(
            get: { settings.audioOptions.allowedPassthru.contains(codec) },
            set: { on in
                var next = settings.audioOptions.allowedPassthru
                if on { next.insert(codec) } else { next.remove(codec) }
                settings.audioOptions.allowedPassthru = next
            }
        )
    }
}
