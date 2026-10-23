import SwiftUI

/// The eight tabs as a native segmented control of symbols, with the selected tab's
/// name and shortcut under it (the way system inspectors label their tab strips).
struct SettingsTabBar: View {
    @Environment(AppModel.self) private var model

    private var tab: SettingsTab { model.ui.detailTab }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker("Settings", selection: Bindable(model.ui).detailTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .help(tab.title)
                        .accessibilityLabel(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            HStack {
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .id(tab)
                    .motionTransition(.content)
                Spacer()
                if let digit = SettingsTab.shortcutDigit(at: SettingsTab.allCases.firstIndex(of: tab) ?? 0) {
                    Text(verbatim: "⌥⌘\(digit)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .motion(Motion.quick, value: tab)
        }
    }
}
