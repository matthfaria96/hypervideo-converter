import HyperVideoCore
import SwiftUI

/// The colour families tags use, so every status reads the same everywhere.
enum TagTone: Hashable {
    case neutral, accent, success, warning, danger, info, purple, teal

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .accent: Theme.accentText
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .info: Color(light: 0x1F6FD1, dark: 0x6AB0FF)
        case .purple: Color(light: 0x7B3FD1, dark: 0xC29BFF)
        case .teal: Color(light: 0x0F8A8A, dark: 0x5ED6D6)
        }
    }
}

/// A small coloured pill: icon and text, optionally with a live dot that pulses.
struct StatusTag: View {
    let text: String
    var symbol: String?
    var tone: TagTone = .neutral
    var isLive = false

    var body: some View {
        HStack(spacing: 4) {
            if isLive {
                PulsingDot(color: tone.color)
            } else if let symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(verbatim: text).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tone.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(tone == .neutral ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(tone.color.opacity(0.15)), in: .capsule)
        .fixedSize()
    }
}

/// A dot that breathes while something is running.
struct PulsingDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.35)
            .scaleEffect(on ? 1 : 0.7)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// What a job's state looks like: label, symbol and colour.
struct JobStatusLook: Equatable {
    let title: String
    let symbol: String
    let tone: TagTone
    /// Shown with a pulsing dot.
    let isLive: Bool

    init(_ state: JobState) {
        switch state {
        case .queued:
            (title, symbol, tone, isLive) = (String(localized: "Waiting"), "clock", .neutral, false)
        case .running:
            (title, symbol, tone, isLive) = (String(localized: "Converting"), "gearshape.2", .accent, true)
        case .completed:
            (title, symbol, tone, isLive) = (String(localized: "Completed"), "checkmark.circle.fill", .success, false)
        case .failed:
            (title, symbol, tone, isLive) = (String(localized: "Failed"), "exclamationmark.triangle.fill", .danger, false)
        case .cancelled:
            (title, symbol, tone, isLive) = (String(localized: "Cancelled"), "stop.circle", .neutral, false)
        }
    }

    var tag: StatusTag { StatusTag(text: title, symbol: symbol, tone: tone, isLive: isLive) }
}

/// Which mode made a job: Convert, Compress or AI Upscale.
struct JobKindLook: Equatable {
    let kind: WorkMode

    init(settings: EncodeSettings, presetID: UUID?) {
        if settings.upscale != nil {
            kind = .upscale
        } else if let presetID, QualityProfile.isCompressPreset(presetID) {
            kind = .compress
        } else {
            kind = .convert
        }
    }

    var tag: StatusTag { StatusTag(text: kind.tagTitle, symbol: kind.symbol, tone: kind.tone) }
}

extension WorkMode {
    var tone: TagTone {
        switch self {
        case .convert: .info
        case .compress: .teal
        case .upscale: .purple
        }
    }

    var tagTitle: String {
        switch self {
        case .convert: String(localized: "Convert")
        case .compress: String(localized: "Compress")
        case .upscale: String(localized: "AI Upscale")
        }
    }
}

/// "−40%" in green when the file got smaller, "+150%" in orange when larger.
struct SizeChangeLook: Equatable {
    let text: String
    let tone: TagTone

    init?(before: Int64, after: Int64) {
        guard before > 0, after > 0 else { return nil }
        let change = Int(((Double(after) / Double(before) - 1) * 100).rounded())
        switch change {
        case ..<(-1): (text, tone) = ("−\(-change)%", .success)
        case 2...: (text, tone) = ("+\(change)%", .warning)
        default: (text, tone) = (String(localized: "Same size"), .neutral)
        }
    }

    var tag: StatusTag {
        StatusTag(text: text, symbol: tone == .success ? "arrow.down.right" : tone == .warning ? "arrow.up.right" : nil, tone: tone)
    }
}

/// A container's tag colour: each common format has its own, so lists scan quickly.
enum ContainerTag {
    static func tone(for format: String) -> TagTone {
        switch format.uppercased() {
        case "MP4": .info
        case "MOV": .purple
        case "MKV": .teal
        case "M4V": .accent
        default: .neutral
        }
    }
}
