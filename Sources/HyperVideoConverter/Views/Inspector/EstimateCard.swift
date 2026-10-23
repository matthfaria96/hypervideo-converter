import SwiftUI

/// "Size estimate": real numbers where the settings make the size predictable.
struct EstimateCard: View {
    @Environment(AppModel.self) private var model
    /// One video's estimate; nil shows the inspector targets'.
    var estimate: SizeEstimate?

    var body: some View {
        let estimate = self.estimate ?? model.sizeEstimate
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Eyebrow(text: "Size estimate")
                Spacer()
                Text(verbatim: kindLabel(estimate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: headline(estimate))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text(verbatim: badge(estimate))
                    .font(.callout)
                    .foregroundStyle(estimate.savings.map { $0 >= 0 } ?? false ? Theme.success : .secondary)
                    .contentTransition(.numericText())
            }
            Text(verbatim: note(estimate))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .card(.raised)
        .motion(Motion.snappy, value: estimate)
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
