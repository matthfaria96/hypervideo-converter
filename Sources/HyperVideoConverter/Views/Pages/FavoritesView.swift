import HyperVideoCore
import SwiftUI
import UniformTypeIdentifiers

/// Presets: apply, make default, save, rename, delete, import (HyperVideo or HandBrake) and export.
struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.defaultPresetID) private var defaultID = ""

    var body: some View {
        @Bindable var ui = model.ui

        PageScaffold(eyebrow: "Library", title: "Favorites",
                     subtitle: "Presets apply to the selected videos, or to every video in the list.") {
            HStack(spacing: 8) {
                Button("Save Current Settings…", systemImage: "plus") {
                    ui.presetName = ""
                    ui.isSavingPreset = true
                }
                .buttonStyle(.subtle)
                Menu("More", systemImage: "ellipsis") {
                    Button("Import Presets…", systemImage: "square.and.arrow.down") { PresetFiles.importPresets(model) }
                        .help("HyperVideo or HandBrake preset exports (.json)")
                    Button("Export My Presets…", systemImage: "square.and.arrow.up") { PresetFiles.exportPresets(model) }
                        .disabled(model.presets.custom.isEmpty)
                }
                .menuStyle(.button)
                .fixedSize()
            }
        } content: {
            ForEach(model.presets.grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: LocalizedStringKey(group.presets.first?.displayCategory ?? group.category))
                    VStack(spacing: 0) {
                        ForEach(group.presets) { preset in
                            PresetRow(preset: preset, isDefault: preset.id == model.defaultPreset.id)
                                .padding(12)
                                .overlay(alignment: .bottom) { Color(hex: 0x333338).frame(height: 1) }
                                .contextMenu { menu(for: preset) }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 11))
                    .card(fill: Color(hex: 0x202023))
                }
            }
        }
        .alert("Save Preset", isPresented: $ui.isSavingPreset) {
            TextField("Name", text: $ui.presetName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the output settings shown in the inspector as a reusable preset.")
        }
        .alert("Rename Preset", isPresented: .constant(ui.renamingPreset != nil)) {
            TextField("Name", text: $ui.presetName)
            Button("Rename") {
                if let renaming = ui.renamingPreset { model.presets.rename(renaming.id, to: ui.presetName) }
                ui.renamingPreset = nil
            }
            Button("Cancel", role: .cancel) { ui.renamingPreset = nil }
        }
    }

    @ViewBuilder
    private func menu(for preset: Preset) -> some View {
        Button("Apply", systemImage: "checkmark") { model.applyPresetToTargets(preset) }
        Button("Make Default", systemImage: "star") { defaultID = preset.id.uuidString }
        if !preset.isBuiltIn {
            Divider()
            Button("Update from Current Settings", systemImage: "arrow.triangle.2.circlepath") {
                model.presets.update(preset.id, settings: model.inspectorSettings)
            }
            Button("Rename…", systemImage: "pencil") {
                model.ui.presetName = preset.name
                model.ui.renamingPreset = preset
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.presets.delete(preset.id) }
        }
    }

    private func saveCurrent() {
        let preset = model.presets.save(name: model.ui.presetName, category: String(localized: "My Presets"),
                                        settings: model.inspectorSettings)
        model.inspectorTargetIDs.forEach { id in model.update(id) { $0.presetID = preset.id } }
    }
}

private struct PresetRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.defaultPresetID) private var defaultID = ""
    let preset: Preset
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: preset.symbol)
                .font(.system(size: 13))
                .foregroundStyle(isDefault ? Theme.accentLight : Color(hex: 0xDDDDDD))
                .frame(width: 30, height: 30)
                .background(isDefault ? Color(hex: 0x594421) : Color(hex: 0x39393F), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: preset.displayName).font(.system(size: 12, weight: .semibold))
                    if isDefault {
                        Text("Default").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accentLight)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accentWash, in: .capsule)
                    }
                }
                Text(verbatim: preset.displaySummary).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Button("Make Default", systemImage: isDefault ? "star.fill" : "star") { defaultID = preset.id.uuidString }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.ghost)
                    .help(isDefault ? "This is the default profile for new videos" : "Make this the default profile for new videos")
                    .accessibilityLabel(Text("Make Default"))
                    .accessibilityAddTraits(isDefault ? .isSelected : [])
                Button("Apply") { model.applyPresetToTargets(preset) }
                    .buttonStyle(.subtle)
                    .help("Apply to the selected videos, or to all when none is selected")
            }
        }
        .contentShape(.rect)
    }
}

/// Preset import and export through open and save panels.
@MainActor
enum PresetFiles {
    static func importPresets(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let (count, notes) = try model.presets.importPresets(from: url)
            var message = String(localized: "Imported \(count) presets.")
            if !notes.isEmpty {
                let shown = notes.prefix(6).joined(separator: "\n")
                let more = notes.count > 6 ? "\n" + String(localized: "…and \(notes.count - 6) more adjustments.") : ""
                message += "\n\n" + String(localized: "Adjusted to what HyperVideo supports:") + "\n" + shown + more
            }
            model.showAlert(String(localized: "Profiles imported"), message)
        } catch {
            model.showAlert(String(localized: "Couldn't import profiles"),
                            String(localized: "That file isn't a HyperVideo or HandBrake preset export."))
        }
    }

    static func exportPresets(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HyperVideo Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.presets.exportPresets(to: url)
        } catch {
            model.showAlert(String(localized: "Couldn't export profiles"), error.localizedDescription)
        }
    }
}
