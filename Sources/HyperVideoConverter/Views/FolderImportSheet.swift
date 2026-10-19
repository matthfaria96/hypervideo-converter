import HyperVideoCore
import SwiftUI

/// Asks which preset the videos in imported folders get, defaulting to the default preset.
struct FolderImportSheet: View {
    @Environment(AppModel.self) private var model
    let pending: FolderImport

    /// The choice lives in the model's pending import (this toolchain has no `@State`).
    private var presetID: Binding<UUID?> {
        Binding(get: { model.pendingFolderImport?.presetID }, set: { model.pendingFolderImport?.presetID = $0 })
    }

    private var title: String {
        pending.folders.count == 1
            ? String(localized: "Import “\(pending.folders[0].lastPathComponent)”")
            : String(localized: "Import \(pending.folders.count) Folders")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "folder.badge.plus").font(.title3.weight(.semibold))
            Text("Every video found in the folder and its subfolders gets this profile. You can still change each one afterwards.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Profile", selection: presetID) {
                ForEach(model.presets.grouped, id: \.category) { group in
                    Section(group.presets.first?.displayCategory ?? group.category) {
                        ForEach(group.presets) { Text(verbatim: $0.displayName).tag(Optional($0.id)) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelFolderImport() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    model.confirmFolderImport(preset: model.presets.preset(id: presetID.wrappedValue) ?? model.defaultPreset)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
