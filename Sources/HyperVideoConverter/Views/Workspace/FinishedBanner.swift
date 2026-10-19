import SwiftUI

/// "3 videos ready in ~/Movies [Open Folder]" after a run finishes.
struct FinishedBanner: View {
    @Environment(AppModel.self) private var model
    let count: Int
    let folder: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: count == 1 ? String(localized: "1 video ready") : String(localized: "\(count) videos ready"))
                    .font(.system(size: 12, weight: .semibold))
                Text(verbatim: String(localized: "Saved in \(Format.path(folder))"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Button("Open Folder", systemImage: "folder") { NSWorkspace.shared.open(folder) }
                .buttonStyle(.subtle)
            Button {
                model.dismissFinishedBatch()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(RemoveButtonStyle())
            .help("Dismiss")
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(12)
        .card(fill: Color(hex: 0x1F2A22), radius: 11, stroke: Color(hex: 0x2F5A3C))
    }
}
