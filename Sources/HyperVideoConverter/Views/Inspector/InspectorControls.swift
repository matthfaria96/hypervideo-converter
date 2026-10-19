import SwiftUI

/// A full-width pop-up field in the prototype's style.
struct MenuField<Value: Hashable & Identifiable>: View {
    let label: LocalizedStringKey
    let selection: Value
    let options: [Value]
    let title: (Value) -> LocalizedStringKey
    let choose: @MainActor @Sendable (Value) -> Void

    var body: some View {
        Menu {
            Picker(label, selection: Binding(get: { selection }, set: choose)) {
                ForEach(options) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack {
                Text(title(selection)).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: 0xF2F2F4))
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .card(fill: Color(hex: 0x2B2B2F), radius: 8, stroke: Color(hex: 0x45454B))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(label))
    }
}

/// The prototype's small green switch.
struct PillSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            Capsule()
                .fill(configuration.isOn ? Color(hex: 0x4CAE73) : Color(hex: 0x55555B))
                .frame(width: 31, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                }
                .animation(.smooth(duration: 0.15), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityAddTraits(.isButton)
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}
