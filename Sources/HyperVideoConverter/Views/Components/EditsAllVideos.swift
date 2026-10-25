import SwiftUI

extension EnvironmentValues {
    /// The tabs edit every target video at once. Per-video parts (trim, crop, track lists,
    /// chapter names, title) can't change for all videos together, so they turn into a hint.
    @Entry var editsAllVideos = false
}

/// The hint shown where a per-video setting would be when the tabs edit every video.
struct PerVideoHint: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "hand.point.left")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
