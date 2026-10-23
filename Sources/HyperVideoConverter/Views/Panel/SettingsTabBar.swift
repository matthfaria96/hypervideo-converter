import SwiftUI

/// Eight equal-width tabs with an accent wash and underline on the selected one.
struct SettingsTabBar: View {
    @Environment(AppModel.self) private var model
    @State private var hovered: SettingsTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases) { tab in
                button(for: tab)
            }
        }
        .animation(.smooth(duration: 0.15), value: model.ui.detailTab)
    }

    private func button(for tab: SettingsTab) -> some View {
        let selected = model.ui.detailTab == tab
        return Button { model.ui.detailTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 13))
                Text(tab.title).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.accentLight : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(selected ? Theme.accentWash : (hovered == tab ? Theme.panelRaised : Color.clear))
            .overlay(alignment: .bottom) {
                if selected { Theme.accent.frame(height: 2) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
