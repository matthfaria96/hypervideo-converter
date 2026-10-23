import HyperVideoCore
import SwiftUI

/// The AI models as the same cards the quality profiles use, each tagged with how fast
/// it is, so the slow ones are a choice made knowingly.
struct UpscaleModelPicker: View {
    @Binding var selection: UpscaleModel

    var body: some View {
        SettingsSection(title: "AI Model", symbol: "cpu") {
            VStack(spacing: Spacing.s) {
                ForEach(UpscaleModel.allCases) { model in
                    ChoiceCard(symbol: Self.symbol(model),
                               title: String(localized: String.LocalizationValue(model.displayName)),
                               tag: Self.speedTag(model),
                               summary: String(localized: String.LocalizationValue(model.summary)),
                               isSelected: model == selection) { selection = model }
                }
            }
            .motion(value: selection)
        }
    }

    static func symbol(_ model: UpscaleModel) -> String {
        switch model {
        case .lite: "hare"
        case .digitalArt: "paintpalette"
        case .standard: "photo"
        case .highFidelity: "sparkle.magnifyingglass"
        }
    }

    /// "Recommended", "Slow", "Very slow" from the model's measured speed (the fast model
    /// is already called Fast, so its tag recommends it instead of repeating the name).
    static func speedTag(_ model: UpscaleModel) -> StatusTag {
        switch model.secondsPerSourceMegapixel {
        case ..<2: StatusTag(text: String(localized: "Recommended"), tone: .success)
        case ..<10: StatusTag(text: String(localized: "Slow"), tone: .warning)
        default: StatusTag(text: String(localized: "Very slow"), tone: .danger)
        }
    }
}
