import HyperVideoCore
import SwiftUI

/// Descriptive tags written to the output (TAG-01…08).
struct TagsSettingsTab: View {
    @Binding var settings: EncodeSettings
    @Environment(\.editsAllVideos) private var editsAllVideos

    /// One label column, so every field starts at the same x.
    private static let labelWidth: CGFloat = 92

    var body: some View {
        SettingsSection(title: "Tags", symbol: "tag") {
            Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s + 2) {
                if !editsAllVideos { field("Title", \.title) }
                field("Actors", \.actors)
                field("Director", \.director)
                field("Release Date", \.releaseDate, prompt: String(localized: "YYYY-MM-DD"))
                field("Comment", \.comment)
                field("Genre", \.genre)
                field("Description", \.description)
                GridRow(alignment: .top) {
                    label("Plot").padding(.top, 5)
                    TextEditor(text: text(\.plot))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Radius.s))
                        .overlay { RoundedRectangle(cornerRadius: Radius.s).strokeBorder(.separator) }
                }
            }
            if editsAllVideos {
                PerVideoHint(text: "The title belongs to one video. Select it in the list to name it.")
            }
            Text("Saved into MP4, MOV and MKV files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Self.labelWidth, alignment: .leading)
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
        GridRow {
            label(title)
            TextField(title, text: text(keyPath), prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }
}
