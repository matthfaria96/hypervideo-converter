import SwiftUI

/// A titled card used for every settings group.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m + 2) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .labelStyle(SectionLabelStyle())
            content
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Section titles: a secondary symbol with the headline beside it.
private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.s) {
            configuration.icon.foregroundStyle(.secondary).frame(width: 18)
            configuration.title
        }
    }
}

/// Compact metadata pill (resolution, codec, frame rate…).
struct InfoChip: View {
    let symbol: String
    let text: String
    var tint: Color?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, Spacing.s + 2)
            .padding(.vertical, Spacing.xs + 1)
            .background(tint.map { AnyShapeStyle($0.opacity(0.22)) } ?? AnyShapeStyle(.fill.tertiary), in: .capsule)
    }
}

/// One setting, laid out the way macOS settings are: the label on the left, the control
/// against the right edge, the explanation under the whole row. A long label wraps beside
/// the control; only a control too wide to share the line (a grid, a long segmented
/// picker) goes on its own line under the label.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SettingRowLayout {
                Text(title)
                control
            }
            if let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Places a label and a control side by side, the control at its own width against the
/// trailing edge, or stacks them when the control leaves the label less than
/// `minLabelWidth`.
private struct SettingRowLayout: Layout {
    var spacing: CGFloat = Spacing.m
    var stackSpacing: CGFloat = Spacing.s
    var minLabelWidth: CGFloat = 72

    private struct Arrangement {
        let label: CGSize
        let control: CGSize
        let sideBySide: Bool
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? idealWidth(subviews)
        let row = arrange(width: width, subviews)
        return row.sideBySide
            ? CGSize(width: width, height: max(row.label.height, row.control.height))
            : CGSize(width: width, height: row.label.height + stackSpacing + row.control.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let row = arrange(width: bounds.width, subviews)
        if row.sideBySide {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(row.label))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                              proposal: ProposedViewSize(row.control))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(row.label))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + row.label.height + stackSpacing),
                              anchor: .topLeading, proposal: ProposedViewSize(row.control))
        }
    }

    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        subviews[0].sizeThatFits(.unspecified).width + spacing + subviews[1].sizeThatFits(.unspecified).width
    }

    /// The control first gets the width the label can spare; a control that needs more
    /// than that moves under the label at the full width.
    private func arrange(width: CGFloat, _ subviews: Subviews) -> Arrangement {
        let labelIdeal = subviews[0].sizeThatFits(.unspecified).width
        let room = width - spacing - min(labelIdeal, minLabelWidth)
        let control = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil))
        if control.width <= room + 0.5 {
            let labelWidth = max(0, width - spacing - control.width)
            let label = subviews[0].sizeThatFits(ProposedViewSize(width: labelWidth, height: nil))
            return Arrangement(label: CGSize(width: labelWidth, height: label.height), control: control, sideBySide: true)
        }
        let label = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let stacked = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return Arrangement(label: label, control: CGSize(width: min(stacked.width, width), height: stacked.height),
                           sideBySide: false)
    }
}

/// Warnings shown verbatim: pass already-localized text (`String(localized:)`).
struct StatusBanner: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12), in: .rect(cornerRadius: Radius.m))
        .overlay { RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Theme.warning.opacity(0.35)) }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "12,0 Mbit/s" in Portuguese, "12.0 Mbit/s" in English.
    static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? "\((bitsPerSecond / 1_000_000).formatted(.number.precision(.fractionLength(1)))) Mbit/s"
            : "\((bitsPerSecond / 1_000).formatted(.number.precision(.fractionLength(0)))) kbit/s"
    }

    /// A folder path with the home folder shortened to ~.
    static func path(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Encode speed relative to playback, e.g. "3.2×", or "0.03×" for slow work like AI Upscale.
    static func speed(_ multiple: Double) -> String {
        let digits = multiple < 0.1 ? 2 : multiple < 10 ? 1 : 0
        return "\(multiple.formatted(.number.precision(.fractionLength(digits))))×"
    }

    static func size(_ size: CGSize) -> String { "\(Int(size.width)) × \(Int(size.height))" }

    static func fps(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) fps"
    }
}
