import SwiftUI

/// A full-width native pop-up button.
struct MenuField<Value: Hashable & Identifiable>: View {
    let label: LocalizedStringKey
    let selection: Value
    let options: [Value]
    let title: (Value) -> LocalizedStringKey
    let choose: @MainActor @Sendable (Value) -> Void

    var body: some View {
        Picker(label, selection: Binding(get: { selection }, set: choose)) {
            ForEach(options) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(label))
    }
}

/// A switch with a title and a one-line explanation, the switch at the trailing edge.
struct SwitchRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isOn: Bool
    let set: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }
}
