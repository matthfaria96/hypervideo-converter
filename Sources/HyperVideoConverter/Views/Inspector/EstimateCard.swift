import SwiftUI

/// "Size estimate": real numbers where the settings make the size predictable.
struct EstimateCard: View {
    @Environment(AppModel.self) private var model
    /// One video's estimate; nil shows the inspector targets'.
    var estimate: SizeEstimate?

    var body: some View {
        let estimate = self.estimate ?? model.sizeEstimate
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SIZE ESTIMATE")
                Spacer()
                Text(verbatim: kindLabel(estimate))
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

    private func kindLabel(_ estimate: SizeEstimate) -> String {
        guard estimate.estimatedBytes != nil else { return "" }
        switch estimate.kind {
        case .exact: return String(localized: "copied as is")
        case .upTo: return String(localized: "maximum")
        case .approximate: return String(localized: "≈ estimate")
        }
    }

    private func headline(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else { return "—" }
        guard let bytes = estimate.estimatedBytes else { return String(localized: "Depends on content") }
        return SizeEstimate.label(bytes: bytes, kind: estimate.kind)
    }

    private func badge(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else { return String(localized: "Add a video") }
        guard let savings = estimate.savings else { return String(localized: "Original: \(Format.bytes(estimate.originalBytes))") }
        let percent = Int((abs(savings) * 100).rounded())
        if percent < 1 { return String(localized: "About the same size") }
        return savings > 0 ? String(localized: "−\(percent)% estimated") : String(localized: "+\(percent)% larger")
    }

    private func note(_ estimate: SizeEstimate) -> String {
        guard estimate.count > 0 else {
            return String(localized: "The estimate depends on the original video, the codec and the settings you choose.")
        }
        switch estimate.kind {
        case .exact: return String(localized: "The video is copied without re-encoding, so the size barely changes.")
        case .upTo: return String(localized: "With a fixed bitrate the file usually ends up at or below this size.")
        case .approximate:
            return String(localized: "A rule of thumb from resolution, frame rate and quality. Detailed or shaky videos come out larger, still ones smaller.")
        }
    }
}
