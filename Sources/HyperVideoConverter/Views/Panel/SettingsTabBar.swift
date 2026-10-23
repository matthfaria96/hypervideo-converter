import SwiftUI

/// The eight HandBrake tabs as two rows of four, each with its icon and name, filling
/// the panel's width. The selected tab is filled with the accent and slides between tabs.
struct SettingsTabBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    private var current: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(Array(SettingsTab.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Spacing.xs) {
                    ForEach(row) { tab in button(tab) }
                }
            }
        }
        .padding(Spacing.xs)
        .background(.fill.quaternary, in: .rect(cornerRadius: Radius.m + 2))
        .motion(Motion.snappy, value: current)
    }

    private func button(_ tab: SettingsTab) -> some View {
        let selected = tab == current
        return Button { model.ui.detailTab = tab } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                Text(tab.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selected ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs + 1)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.m)
                        .fill(Theme.accent)
                        .matchedGeometryEffect(id: "selected", in: selection)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverLift(1.03)
        .help(Text(tab.title) + Text(verbatim: shortcut(tab)))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func shortcut(_ tab: SettingsTab) -> String {
        guard let digit = SettingsTab.shortcutDigit(at: SettingsTab.allCases.firstIndex(of: tab) ?? 0) else { return "" }
        return " (⌥⌘\(digit))"
    }
}
