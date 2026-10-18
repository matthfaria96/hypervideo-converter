import HyperVideoCore
import SwiftUI
import UniformTypeIdentifiers

struct PresetInspector: View {
    @Environment(AppModel.self) private var model
    private var ui: UIState { model.ui }

    private var source: SourceItem? { model.selectedSource }

    var body: some View {
        @Bindable var ui = ui

        return List {
            ForEach(model.presets.grouped, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.presets) { preset in
                        PresetRow(preset: preset, isSelected: source?.presetID == preset.id)
                            .contentShape(.rect)
                            .onTapGesture { apply(preset) }
                            .contextMenu { menu(for: preset) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
        .alert("Save Preset", isPresented: $ui.isSavingPreset) {
            TextField("Name", text: $ui.presetName)
            Button("Save") { saveCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current video's settings as a reusable preset.")
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

    private var footer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button("Save as Preset", systemImage: "plus") {
                    ui.presetName = ""
                    ui.isSavingPreset = true
                }
                .buttonStyle(.glass)
                .disabled(source == nil)

                Menu("More", systemImage: "ellipsis") {
                    Button("Import Presets…", systemImage: "square.and.arrow.down") { importPresets() }
                    Button("Export My Presets…", systemImage: "square.and.arrow.up") { exportPresets() }
                        .disabled(model.presets.custom.isEmpty)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .labelStyle(.iconOnly)
                .fixedSize()
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func menu(for preset: Preset) -> some View {
        Button("Apply", systemImage: "checkmark") { apply(preset) }
            .disabled(source == nil)
        Button("Make Default", systemImage: "star") {
            UserDefaults.standard.set(preset.id.uuidString, forKey: PreferenceKey.defaultPresetID)
        }
        if !preset.isBuiltIn {
            Divider()
            if let source {
                Button("Update from Current Video", systemImage: "arrow.triangle.2.circlepath") {
                    model.presets.update(preset.id, settings: source.settings)
                }
            }
            Button("Rename…", systemImage: "pencil") {
                ui.presetName = preset.name
                ui.renamingPreset = preset
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.presets.delete(preset.id) }
        }
    }

    private func apply(_ preset: Preset) {
        guard let id = source?.id else { return }
        withAnimation(.smooth) { model.applyPreset(preset, to: id) }
    }

    private func saveCurrent() {
        guard let source else { return }
        let preset = model.presets.save(name: ui.presetName, category: "My Presets", settings: source.settings)
        model.update(source.id) { $0.presetID = preset.id }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try model.presets.importPresets(from: url)
            model.alertMessage = "Imported \(count) preset\(count == 1 ? "" : "s")."
        } catch {
            model.alertMessage = "That file isn't a HyperVideo preset export."
        }
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HyperVideo Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.presets.exportPresets(to: url)
        } catch {
            model.alertMessage = "Couldn't export presets: \(error.localizedDescription)"
        }
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: preset.symbol)
                .frame(width: 30, height: 30)
                .glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.5)) : .regular, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).fontWeight(isSelected ? .semibold : .regular)
                Text(preset.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }
}
