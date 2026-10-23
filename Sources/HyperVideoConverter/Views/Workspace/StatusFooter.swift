import SwiftUI

/// The strip under the list: counts and sizes on the left, quick ways to History,
/// Favorites and Analyze on the right (with the history count), and a local-only note.
struct StatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(verbatim: summary)
                .contentTransition(.numericText())
            if model.queue.runningCount > 0 {
                Text(verbatim: "·")
                Text(verbatim: model.statusText).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: Spacing.s)
            Image(systemName: "lock.shield")
                .help("Local processing · Your videos are never uploaded to the cloud")
            Divider().frame(height: 14)
            ForEach(AppSection.pages) { page in
                pageButton(page)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs + 2)
        .motion(Motion.snappy, value: summary)
    }

    private func pageButton(_ page: AppSection) -> some View {
        Button {
            model.presentedPage = page
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: page.symbol)
                Text(page.title)
                if page == .history && !model.historyJobs.isEmpty {
                    Text(model.historyJobs.count, format: .number)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .background(.fill.tertiary, in: .capsule)
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .disabled(page == .analyze && model.sources.isEmpty)
        .help(page.title)
    }

    /// "3 videos · 1.2 GB · 1 selected"
    private var summary: String {
        let count = model.sources.count
        var parts = [count == 1 ? String(localized: "1 video") : String(localized: "\(count) videos")]
        let bytes = model.sources.compactMap { $0.info?.fileBytes }.reduce(0, +)
        if bytes > 0 { parts.append(Format.bytes(bytes)) }
        if !model.selectedIDs.isEmpty { parts.append(String(localized: "\(model.selectedIDs.count) selected")) }
        if model.queue.pendingCount > 0 { parts.append(String(localized: "\(model.queue.pendingCount) waiting")) }
        return parts.joined(separator: " · ")
    }
}
