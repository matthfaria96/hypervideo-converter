import SwiftUI

/// "3 videos ready in ~/Movies [Open Folder]" after a run finishes.
struct FinishedBanner: View {
    @Environment(AppModel.self) private var model
    let count: Int
    let folder: URL

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.success)
                .symbolEffect(.bounce, value: count)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: count == 1 ? String(localized: "1 video ready") : String(localized: "\(count) videos ready"))
                    .font(.body.weight(.semibold))
                Text(verbatim: String(localized: "Saved in \(Format.path(folder))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: Spacing.s)
            Button("Open Folder", systemImage: "folder") { NSWorkspace.shared.open(folder) }
                .compatGlassButtonStyle()
            RowRemoveButton(help: "Dismiss", label: String(localized: "Dismiss")) { model.dismissFinishedBatch() }
        }
        .padding(Spacing.m)
        .card(.raised, radius: Radius.l)
    }
}
