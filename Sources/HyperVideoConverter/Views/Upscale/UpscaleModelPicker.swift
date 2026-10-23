import HyperVideoCore
import SwiftUI

/// The AI models as cards, each with how fast it is, so the slow ones are a choice
/// made knowingly.
struct UpscaleModelPicker: View {
    @Binding var selection: UpscaleModel

    var body: some View {
        SettingsSection(title: "AI Model", symbol: "cpu") {
            VStack(spacing: Spacing.s) {
                ForEach(UpscaleModel.allCases) { model in card(model) }
            }
        }
    }

    private func card(_ model: UpscaleModel) -> some View {
        let selected = model == selection
        return Button { selection = model } label: {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs + 2) {
                        Text(localizing: model.displayName).font(.body.weight(.medium))
                        SpeedTag(model: model)
                    }
                    Text(localizing: model.summary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Spacing.m)
            .card(selected ? .selected : .standard)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverLift()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "Recommended", "Slow", "Very slow" from the model's measured speed (the fast model
/// is already called Fast, so its tag recommends it instead of repeating the name).
private struct SpeedTag: View {
    let model: UpscaleModel

    var body: some View {
        let (text, tint): (LocalizedStringKey, Color) = switch model.secondsPerSourceMegapixel {
        case ..<2: ("Recommended", Theme.success)
        case ..<10: ("Slow", Theme.warning)
        default: ("Very slow", Theme.danger)
        }
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: .capsule)
    }
}
