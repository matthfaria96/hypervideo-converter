import HyperVideoCore
import SwiftUI

/// Descriptive tags written to the output (TAG-01…08).
struct TagsSettingsTab: View {
    @Binding var settings: EncodeSettings

    var body: some View {
        SettingsSection(title: "Tags", symbol: "tag") {
            field("Title", \.title)
            field("Actors", \.actors)
            field("Director", \.director)
            field("Release Date", \.releaseDate, prompt: String(localized: "YYYY-MM-DD"))
            field("Comment", \.comment)
            field("Genre", \.genre)
            field("Description", \.description)
            SettingRow(title: "Plot") {
                TextEditor(text: text(\.plot))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72)
                    .background(.fill.tertiary, in: .rect(cornerRadius: Radius.s))
            }
            Text("Saved into MP4, MOV and MKV files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func text(_ keyPath: WritableKeyPath<MetadataTags, String?>) -> Binding<String> {
        Binding(
            get: { settings.tags[keyPath: keyPath] ?? "" },
            set: { settings.tags = settings.tags.setting(keyPath, $0) }
        )
    }

    private func field(
        _ title: LocalizedStringKey, _ keyPath: WritableKeyPath<MetadataTags, String?>, prompt: String = ""
    ) -> some View {
        SettingRow(title: title) {
            TextField(title, text: text(keyPath), prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}
