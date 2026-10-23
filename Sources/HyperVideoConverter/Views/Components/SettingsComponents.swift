import SwiftUI

/// A titled card used for every settings group.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
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

private struct SettingsLabelWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 160 }

extension EnvironmentValues {
    /// Width of the label column of `SettingRow` (narrower in the inspector).
    var settingsLabelWidth: CGFloat {
        get { self[SettingsLabelWidthKey.self] }
        set { self[SettingsLabelWidthKey.self] = newValue }
    }
}

/// Label and control on one line, aligned on a shared label column; the help text
/// runs under the whole row, so long hints never squeeze the label.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    @ViewBuilder var control: Control
    @Environment(\.settingsLabelWidth) private var labelWidth

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Side by side when the control fits next to the label column; otherwise
            // the label goes above the control, so a wide control never widens its panel.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                    label.frame(width: labelWidth, alignment: .leading)
                    control
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    label
                    control
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var label: some View {
        Text(title).fixedSize(horizontal: false, vertical: true)
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

    /// Encode speed relative to playback, e.g. "3.2×".
    static func speed(_ multiple: Double) -> String {
        "\(multiple.formatted(.number.precision(.fractionLength(multiple < 10 ? 1 : 0))))×"
    }

    static func size(_ size: CGSize) -> String { "\(Int(size.width)) × \(Int(size.height))" }

    static func fps(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) fps"
    }
}
