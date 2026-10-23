import HyperVideoCore
import SwiftUI

/// "Before → after": resolution, file size with how much heavier it gets, and the time
/// it will take — the numbers to decide on before starting a long upscale.
struct UpscalePredictionCard: View {
    let estimate: UpscaleEstimate

    var body: some View {
        // A section like every other card in the panels.
        SettingsSection(title: "Result preview", symbol: "eye") {
            if estimate.count == 0 {
                Text("Add videos to see the new resolution, file size and time before starting.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                resolution
                Divider()
                sizeRow
                SizeBars(before: estimate.sourceBytes, after: estimate.predictedBytes)
                Divider()
                timeRow
                if estimate.anyLimited {
                    Label("Limited to 4K", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .motion(Motion.snappy, value: estimate)
    }

    @ViewBuilder
    private var resolution: some View {
        if let first = estimate.sizes.first {
            HStack(spacing: Spacing.s) {
                Text(verbatim: Format.size(first.from)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Text(verbatim: Format.size(first.to))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            if estimate.sizes.count > 1 {
                Text("\(estimate.sizes.count) different sizes across \(estimate.count) videos")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var sizeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("File size").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: Spacing.s) {
                    Text(verbatim: Format.bytes(estimate.sourceBytes)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(verbatim: "≈ " + Format.bytes(estimate.predictedBytes))
                        .font(.title2.weight(.semibold))
                        .contentTransition(.numericText())
                }
                .monospacedDigit()
            }
            Spacer()
            if let growth = estimate.growth { GrowthBadge(growth: growth) }
        }
    }

    private var timeRow: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "timer").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("About \(Self.duration(estimate.seconds)) on this Mac")
                    .fontWeight(.medium)
                    .contentTransition(.numericText())
                Text("Each frame goes through the AI model. The queue refines this once it starts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "6 min", "2 h 10 min" — never seconds, the estimate isn't that precise.
    static func duration(_ seconds: Double) -> String {
        let rounded = max(60, (seconds / 60).rounded(.up) * 60)
        return Duration.seconds(rounded).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// "+110%" tinted by how much heavier the file gets.
private struct GrowthBadge: View {
    let growth: Double

    var body: some View {
        let percent = Int((growth * 100).rounded())
        Text(verbatim: percent >= 0 ? "+\(percent)%" : "\(percent)%")
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: .capsule)
            .contentTransition(.numericText())
            .help(Text("How much bigger the new file is than the original"))
    }

    private var tint: Color {
        switch growth {
        case ..<0.75: Theme.success
        case ..<2.5: Theme.warning
        default: Theme.danger
        }
    }
}

/// The original and the predicted size as two bars on the same scale.
private struct SizeBars: View {
    let before: Int64
    let after: Int64

    var body: some View {
        let largest = Double(max(before, after, 1))
        VStack(alignment: .leading, spacing: Spacing.xs) {
            bar(String(localized: "Original"), Double(before) / largest, .secondary)
            bar(String(localized: "Upscaled"), Double(after) / largest, Theme.accent)
        }
        .font(.caption)
        .accessibilityHidden(true)
    }

    private func bar(_ title: String, _ fraction: Double, _ tint: some ShapeStyle) -> some View {
        HStack(spacing: Spacing.s) {
            Text(verbatim: title).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(.fill.tertiary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: max(4, proxy.size.width * fraction))
                    }
            }
            .frame(height: 6)
        }
    }
}
