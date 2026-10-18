import SwiftUI

/// A titled Liquid Glass panel used for every settings group.
struct GlassSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
            .glassEffect(tint.map { .regular.tint($0.opacity(0.35)) } ?? .regular, in: .capsule)
    }
}

/// Label/control row aligned on a shared leading column.
struct SettingRow<Control: View>: View {
    let title: String
    var help: String?
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
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 16))
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
