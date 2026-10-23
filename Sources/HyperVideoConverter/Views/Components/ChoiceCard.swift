import SwiftUI

/// The one selectable card every list of choices uses (quality profiles, AI models):
/// an icon tile, a title with an optional tag, a one-line summary and a check.
struct ChoiceCard: View {
    let symbol: String
    let title: String
    var tag: StatusTag?
    let summary: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? AnyShapeStyle(Theme.accent.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                                in: .rect(cornerRadius: Radius.s + 2))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs + 2) {
                        Text(verbatim: title).font(.body.weight(.medium))
                        if let tag { tag }
                    }
                    Text(verbatim: summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Spacing.m)
            .card(isSelected ? .selected : .standard)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverLift()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title), \(summary)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
