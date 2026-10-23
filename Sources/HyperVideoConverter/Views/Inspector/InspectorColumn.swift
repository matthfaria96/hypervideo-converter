import SwiftUI

/// The right column: one video's full settings when a single video is selected,
/// otherwise the output settings for every video. The two cross-fade.
struct InspectorColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let source = model.panelSource {
                VideoSettingsPanel(source: source)
                    .id(source.id)
                    .motionTransition(.content)
            } else {
                OutputInspector()
                    .motionTransition(.content)
            }
        }
        .motion(value: model.panelSource?.id)
    }
}
