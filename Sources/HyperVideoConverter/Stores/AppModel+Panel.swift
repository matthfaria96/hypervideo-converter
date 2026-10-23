import HyperVideoCore
import SwiftUI

extension AppModel {
    /// The video whose settings fill the right column, or nil for the all-videos inspector.
    var panelSource: SourceItem? {
        guard let source = selectedSource else { return nil }
        if selectedIDs.isEmpty, source.id == ui.dismissedPanelSourceID { return nil }
        return source
    }

    /// Back to the all-videos inspector (a lone video stays dismissed until selected again).
    func closePanel() {
        ui.dismissedPanelSourceID = selectedSource?.id
        selectedIDs = []
    }

    func showFirstVideoSettings() {
        guard let first = sources.first else { return }
        ui.dismissedPanelSourceID = nil
        selectedIDs = [first.id]
    }

    func settingsBinding(for id: UUID) -> Binding<EncodeSettings> {
        Binding(
            get: { self.sources.first { $0.id == id }?.settings ?? EncodeSettings() },
            set: { newValue in self.update(id) { $0.settings = newValue } }
        )
    }
}
