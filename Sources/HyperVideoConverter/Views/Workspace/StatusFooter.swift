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
                Text(verbatim: model.statusText).foregroundStyle(Theme.accentText)
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
        .motion(Motion.snappy, value: hasNewResults)
        .onChange(of: model.historyJobs.count) { old, new in
            if new > old { model.ui.hasUnseenResults = true }
        }
    }

    private func pageButton(_ page: AppSection) -> some View {
        Button {
            model.presentedPage = page
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: page.symbol)
                    // Bounces whenever a conversion lands in History.
                    .symbolEffect(.bounce, value: page == .history ? model.historyJobs.count : 0)
                Text(page.title)
                if page == .history && !model.historyJobs.isEmpty {
                    Text(model.historyJobs.count, format: .number)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hasNewResults ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .background(hasNewResults ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                        .contentTransition(.numericText())
                        .help(hasNewResults ? Text("New results from the last run") : Text("Finished conversions"))
                }
            }
        }
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .disabled(page == .analyze && model.sources.isEmpty)
        .help(page.title)
    }

    /// Results of the last run are waiting in History (until History is opened).
    private var hasNewResults: Bool { model.ui.hasUnseenResults }

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
