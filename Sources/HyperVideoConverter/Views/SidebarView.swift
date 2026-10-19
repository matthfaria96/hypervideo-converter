import SwiftUI

/// Library pages and tools; collapses to icons only.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    private var collapsed: Bool { model.ui.isSidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !collapsed { Eyebrow(text: "Library").padding(.horizontal, 10).padding(.bottom, 6) }
            NavRow(title: "Conversion", symbol: "rectangle.stack", isActive: isActive(.conversion, .convert),
                   progress: model.queue.runningCount > 0 ? model.progress.fraction : nil) {
                model.setMode(.convert)
            }
            NavRow(title: "History", symbol: "clock.arrow.circlepath", isActive: model.section == .history,
                   badge: model.historyJobs.count) { model.section = .history }
            NavRow(title: "Favorites", symbol: "star", isActive: model.section == .favorites) { model.section = .favorites }

            Theme.separator.frame(height: 1).padding(.horizontal, 8).padding(.vertical, 14)

            if !collapsed { Eyebrow(text: "Tools").padding(.horizontal, 10).padding(.bottom, 6) }
            NavRow(title: "Compress", symbol: "arrow.down.to.line", isActive: isActive(.conversion, .compress)) {
                model.setMode(.compress)
            }
            NavRow(title: "Analyze Video", symbol: "magnifyingglass", isActive: model.section == .analyze) {
                model.section = .analyze
            }

            if !collapsed && model.sources.isEmpty && model.activeJobs.isEmpty && model.historyJobs.isEmpty {
                NoteCard().padding(.top, 18)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, collapsed ? 8 : 12)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private func isActive(_ section: AppSection, _ mode: WorkMode) -> Bool {
        model.section == section && model.mode == mode
    }

    private var footer: some View {
        HStack {
            if !collapsed {
                Text(verbatim: "HyperVideo Converter · \(Self.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                Spacer()
            }
            Button {
                model.ui.isSidebarCollapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "sidebar.right" : "sidebar.left")
                    .foregroundStyle(Theme.faint)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand sidebar" : "Collapse sidebar")
            .accessibilityLabel(Text(collapsed ? "Expand sidebar" : "Collapse sidebar"))
        }
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .padding(.horizontal, collapsed ? 0 : 6)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

private struct NavRow: View {
    @Environment(AppModel.self) private var model
    let title: LocalizedStringKey
    let symbol: String
    let isActive: Bool
    var badge = 0
    /// Overall progress of running conversions, shown as a percentage.
    var progress: Double?
    let action: () -> Void

    var body: some View {
        let collapsed = model.ui.isSidebarCollapsed
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                if !collapsed {
                    Text(title).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.accentLight)
                    } else if badge > 0 {
                        Text("\(badge)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .foregroundStyle(isActive ? Theme.accentLight : Color(hex: 0xC6C6CC))
            .padding(.horizontal, collapsed ? 0 : 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .background(isActive ? Theme.accentWash : .clear, in: .rect(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if collapsed && progress != nil {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7).padding(5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityValue(progress.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private struct NoteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quality comes first")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0xDDDDDD))
            Text("Balanced mode keeps the video's essential settings and only reduces size where it's needed.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Color(hex: 0x242427), radius: 10, stroke: Color(hex: 0x39393E))
        .padding(.horizontal, 2)
    }
}
