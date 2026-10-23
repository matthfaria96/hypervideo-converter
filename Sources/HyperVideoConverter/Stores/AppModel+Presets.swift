import Foundation
import HyperVideoCore

/// The panel's single "Preset" picker: quality profiles, device and web presets and the
/// user's own, applied to the selected videos or to all of them.
extension AppModel {
    private var targetItems: [SourceItem] {
        let ids = Set(inspectorTargetIDs)
        return sources.filter { ids.contains($0.id) }
    }

    /// The preset every target was set from; nil when they differ (or the list is
    /// empty and the draft has none).
    var targetsPresetID: UUID? {
        let items = targetItems
        guard let first = items.first else { return draftBasePresetID }
        return items.allSatisfy { $0.presetID == first.presetID } ? first.presetID : nil
    }

    /// What the picker shows: the shared preset (marked when personalised), or "Mixed".
    var targetsPresetTitle: String {
        let items = targetItems
        guard let first = items.first else {
            return presets.preset(id: draftBasePresetID)?.displayName ?? String(localized: "Custom")
        }
        guard targetsPresetID != nil || first.presetID == nil else { return String(localized: "Mixed presets") }
        return presetName(for: first)
    }

    /// Saves the targets' settings as a new preset and names them after it.
    @discardableResult
    func saveTargetsAsPreset(name: String) -> Preset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let preset = presets.save(name: trimmed, category: String(localized: "My Presets"), settings: inspectorSettings)
        inspectorTargetIDs.forEach { id in update(id) { $0.presetID = preset.id } }
        if sources.isEmpty { draftPresetID = preset.id }
        return preset
    }
}
