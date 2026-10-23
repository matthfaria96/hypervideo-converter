import SwiftUI

/// Points the all-videos inspector at the per-video HandBrake settings.
struct AllSettingsHintCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label("All HandBrake settings", systemImage: "slider.horizontal.3")
                .font(.body.weight(.medium))
            Text("Select one video to see every setting: dimensions, filters, video, audio, subtitles, chapters and tags.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.sources.isEmpty {
                Button { model.showFirstVideoSettings() } label: {
                    Text("Show Settings of First Video").frame(maxWidth: .infinity)
                }
                .compatGlassButtonStyle()
                .motionTransition(.pop)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .motion(value: model.sources.isEmpty)
    }
}
