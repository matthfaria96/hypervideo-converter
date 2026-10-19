import SwiftUI

/// A titled panel used for every settings group.
struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.panel, radius: 12)
    }
}

/// Compact metadata pill (resolution, codec, frame rate…).
struct InfoChip: View {
    let symbol: String
    let text: String
    var tint: Color?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background((tint ?? Theme.muted).opacity(tint == nil ? 0.18 : 0.3), in: .capsule)
    }
}

/// Label/control row aligned on a shared leading column.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)
            control
            Spacer(minLength: 0)
        }
    }
}

struct StatusBanner: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Color.orange.opacity(0.14), radius: 10, stroke: Color.orange.opacity(0.35))
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

    static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Mbit/s", bitsPerSecond / 1_000_000)
            : String(format: "%.0f kbit/s", bitsPerSecond / 1_000)
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
