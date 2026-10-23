import HyperVideoCore
import SwiftUI
import UniformTypeIdentifiers

/// Presets: apply, make default, save, rename, delete, import (HyperVideo or HandBrake) and export.
struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.defaultPresetID) private var defaultID = ""

    var body: some View {
        @Bindable var ui = model.ui

        PageScaffold(subtitle: "Presets apply to the selected videos, or to every video in the list.") {
            HStack(spacing: Spacing.s) {
                Button("Save Current Settings…", systemImage: "plus") {
                    ui.presetName = ""
                    ui.isSavingPreset = true
                }
                Menu("More", systemImage: "ellipsis") {
                    Button("Import Presets…", systemImage: "square.and.arrow.down") { PresetFiles.importPresets(model) }
                        .help("HyperVideo or HandBrake preset exports (.json)")
                    Button("Export My Presets…", systemImage: "square.and.arrow.up") { PresetFiles.exportPresets(model) }
                        .disabled(model.presets.custom.isEmpty)
                }
                .menuStyle(.button)
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            .compatGlassButtonStyle()
        } content: {
            ForEach(model.presets.grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Eyebrow(text: LocalizedStringKey(group.presets.first?.displayCategory ?? group.category))
                    ListCard {
                        ForEach(group.presets) { preset in
                            PresetRow(preset: preset, isDefault: preset.id == model.defaultPreset.id)
                                .listCardRow()
                                .contextMenu { menu(for: preset) }
                                .motionTransition(.row)
                        }
                    }
                }
            }
        }
        .motion(value: model.presets.all.map(\.id))
        .motion(Motion.quick, value: defaultID)
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
        HStack(spacing: Spacing.m) {
            Image(systemName: preset.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(isDefault ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .background(isDefault ? AnyShapeStyle(Theme.accent.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                            in: .rect(cornerRadius: Radius.s + 2))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs + 2) {
                    Text(verbatim: preset.displayName).font(.body.weight(.medium))
                    if isDefault {
                        Text("Default").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.14), in: .capsule)
                            .motionTransition(.pop)
                    }
                }
                Text(verbatim: preset.displaySummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s) {
                Button("Make Default", systemImage: isDefault ? "star.fill" : "star") { defaultID = preset.id.uuidString }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.accessoryBar)
                    .foregroundStyle(isDefault ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .help(isDefault ? "This is the default profile for new videos" : "Make this the default profile for new videos")
                    .accessibilityLabel(Text("Make Default"))
                    .accessibilityAddTraits(isDefault ? .isSelected : [])
                Button("Apply") { model.applyPresetToTargets(preset) }
                    .compatGlassButtonStyle()
                    .controlSize(.small)
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
        PanelPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await runImport(from: url, model) }
        }
    }

    private static func runImport(from url: URL, _ model: AppModel) async {
        do {
            let (count, notes) = try await model.presets.importPresets(from: url)
            model.showAlert(String(localized: "Profiles imported"), importMessage(count: count, notes: notes))
        } catch {
            model.showAlert(String(localized: "Couldn't import profiles"),
                            String(localized: "That file isn't a HyperVideo or HandBrake preset export."))
        }
    }

    private static func importMessage(count: Int, notes: [String]) -> String {
        var message = String(localized: "Imported \(count) presets.")
        if !notes.isEmpty {
            let shown = notes.prefix(6).joined(separator: "\n")
            let more = notes.count > 6 ? "\n" + String(localized: "…and \(notes.count - 6) more adjustments.") : ""
            message += "\n\n" + String(localized: "Adjusted to what HyperVideo supports:") + "\n" + shown + more
        }
        return message
    }

    static func exportPresets(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HyperVideo Presets.json"
        PanelPresenter.present(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            runExport(to: url, model)
        }
    }

    private static func runExport(to url: URL, _ model: AppModel) {
        do {
            try model.presets.exportPresets(to: url)
        } catch {
            model.showAlert(String(localized: "Couldn't export profiles"), error.localizedDescription)
        }
    }
}
