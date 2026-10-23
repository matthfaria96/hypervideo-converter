import SwiftUI

/// Points the all-videos inspector at the per-video HandBrake settings.
struct AllSettingsHintCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("All HandBrake settings", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
            Text("Select one video to see every setting: dimensions, filters, video, audio, subtitles, chapters and tags.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !model.sources.isEmpty {
                Button { model.showFirstVideoSettings() } label: {
                    Text("Show Settings of First Video").frame(maxWidth: .infinity)
                }
                .buttonStyle(.subtle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.panel, radius: 12)
    }
}
