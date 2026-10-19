import SwiftUI

/// "Size estimate": real numbers where the settings make the size predictable.
struct EstimateCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let estimate = model.sizeEstimate
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SIZE ESTIMATE")
                Spacer()
                Text(verbatim: "≈")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: headline(estimate))
                    .font(.system(size: 21, weight: .semibold))
                    .kerning(-0.5)
                    .monospacedDigit()
                Spacer()
                Text(verbatim: badge(estimate))
                    .font(.system(size: 11))
                    .foregroundStyle(estimate.savings.map { $0 >= 0 } ?? false ? Color(hex: 0x7BD49A) : Theme.muted)
            }
            Text(verbatim: note(estimate))
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .card(fill: Color(hex: 0x262629), radius: 10, stroke: Color(hex: 0x3C3C41))
    }

    private func headline(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else { return "—" }
        return Format.bytes(estimate.estimatedBytes ?? estimate.originalBytes)
    }

    private func badge(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else { return String(localized: "Add a video") }
        guard let savings = estimate.savings else { return String(localized: "original size") }
        let percent = Int((abs(savings) * 100).rounded())
        if percent < 1 { return String(localized: "About the same size") }
        return savings > 0 ? String(localized: "−\(percent)% estimated") : String(localized: "+\(percent)% larger")
    }

    private func note(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else {
            return String(localized: "The estimate depends on the original video, the codec and the settings you choose.")
        }
        guard estimate.estimatedBytes != nil else {
            return String(localized: "With constant quality the final size depends on motion, noise and detail. Pick an average bitrate in Advanced Settings for a predictable size.")
        }
        return String(localized: "Estimated from the bitrates. The real size can vary slightly.")
    }
}
