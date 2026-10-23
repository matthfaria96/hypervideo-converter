import HyperVideoCore
import SwiftUI

/// "Preset: Balanced ▾" — every quality profile and preset in one place, grouped like
/// HandBrake's presets, plus saving the current settings and managing the list.
struct PresetPicker: View {
    @Environment(AppModel.self) private var model
    @State private var isSaving = false
    @State private var name = ""

    var body: some View {
        Menu {
            ForEach(model.presets.grouped, id: \.category) { group in
                Section {
                    ForEach(group.presets) { preset in
                        Button {
                            model.applyPresetToTargets(preset)
                        } label: {
                            Label(preset.displayName, systemImage: preset.id == model.targetsPresetID ? "checkmark" : preset.symbol)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey(group.presets.first?.displayCategory ?? group.category))
                }
            }
            Divider()
            Button("Save Current Settings as Preset…", systemImage: "square.and.arrow.down") {
                name = ""
                isSaving = true
            }
            Button("Manage Presets…", systemImage: "square.stack") { model.presentedPage = .favorites }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "square.stack")
                    .foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Preset").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: model.targetsPresetTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .card(.raised)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Choose a preset for these videos")
        .motion(Motion.snappy, value: model.targetsPresetTitle)
        .alert("Save Preset", isPresented: $isSaving) {
            TextField("Name", text: $name)
            Button("Save") { model.saveTargetsAsPreset(name: name) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves these output settings as a reusable preset.")
        }
    }
}
