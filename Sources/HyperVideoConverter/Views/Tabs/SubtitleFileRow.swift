import HyperVideoCore
import SwiftUI

/// One external SRT/WebVTT file with language, offset, title and flags.
struct SubtitleFileRow: View {
    @Environment(AppModel.self) private var model
    let file: SubtitleFile
    let sourceID: UUID
    @Binding var settings: EncodeSettings

    static let offsetLimit = 600_000
    private var isBurned: Bool { settings.burnIn == .file(file.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(file.name, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Remove", systemImage: "xmark") { model.removeSubtitleFile(file, from: sourceID) }
                    .labelStyle(.iconOnly)
                    .compatGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .help("Remove")
                    .accessibilityLabel("Remove")
            }
            HStack(spacing: 12) {
                TextField("Language", text: language, prompt: Text("Language"))
                    .frame(width: 90)
                Text("Offset").foregroundStyle(.secondary)
                TextField("Offset", value: offset, format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Stepper("Offset", value: offset, in: -Self.offsetLimit...Self.offsetLimit, step: 100)
                    .labelsHidden()
                Text("ms").foregroundStyle(.secondary)
                TextField("Title", text: title, prompt: Text("Title"))
            }
            .textFieldStyle(.roundedBorder)
            HStack(spacing: 16) {
                Toggle("Default", isOn: flag(\.isDefault)).toggleStyle(.checkbox)
                Toggle("Forced", isOn: flag(\.isForced)).toggleStyle(.checkbox)
                RadioToggle(isOn: isBurned, title: "Burn", help: "Draws this file into the picture") {
                    settings.burnIn = isBurned ? nil : .file(file.url)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .card(.raised)
        .accessibilityElement(children: .contain)
    }

    private func edit(_ change: @escaping (inout SubtitleFile) -> Void) {
        model.updateSubtitleFile(file.url, in: sourceID, change)
    }

    private var language: Binding<String> {
        Binding(get: { file.language ?? "" }, set: { value in edit { $0.language = value.isEmpty ? nil : value } })
    }

    private var title: Binding<String> {
        Binding(get: { file.title ?? "" }, set: { value in edit { $0.title = value.isEmpty ? nil : value } })
    }

    private var offset: Binding<Int> {
        Binding(
            get: { file.offsetMs },
            set: { value in
                let limit = Self.offsetLimit
                edit { $0.offsetMs = min(max(value, -limit), limit) }
            }
        )
    }

    private func flag(_ keyPath: WritableKeyPath<SubtitleFile, Bool>) -> Binding<Bool> {
        Binding(get: { file[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }
}
