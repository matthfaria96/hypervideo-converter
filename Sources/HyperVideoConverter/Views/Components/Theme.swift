import AppKit
import SwiftUI

/// Design tokens. Colors are semantic and follow the system appearance, so the window
/// looks native in light and dark mode and under Liquid Glass; the amber accent is the
/// app's identity.
enum Theme {
    static let accent = Color(hex: 0xFFB52E)
    /// Status colors tuned for both appearances.
    static let success = Color(light: 0x1F9D57, dark: 0x5FD48A)
    static let danger = Color(light: 0xD63B3B, dark: 0xFF7F7F)
    static let warning = Color(light: 0xB7791F, dark: 0xFFC14D)

    static let background = Color(nsColor: .windowBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
}

/// The 8 pt grid.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let s: CGFloat = 6
    static let m: CGFloat = 10
    static let l: CGFloat = 14
    static let xl: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// One value per appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

/// How much a card stands out from its background.
enum CardProminence {
    case standard, raised, selected
}

/// A rounded panel with a hairline border, filled with a system material-aware tint.
struct CardBackground: ViewModifier {
    var prominence: CardProminence = .standard
    var radius: CGFloat = Radius.m

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(stroke, lineWidth: prominence == .selected ? 1.5 : 1) }
    }

    private var fill: AnyShapeStyle {
        switch prominence {
        case .standard: AnyShapeStyle(.fill.quaternary)
        case .raised: AnyShapeStyle(.fill.tertiary)
        case .selected: AnyShapeStyle(Theme.accent.opacity(0.12))
        }
    }

    private var stroke: AnyShapeStyle {
        prominence == .selected ? AnyShapeStyle(Theme.accent.opacity(0.7)) : AnyShapeStyle(.separator.opacity(0.6))
    }
}

extension View {
    func card(_ prominence: CardProminence = .standard, radius: CGFloat = Radius.m) -> some View {
        modifier(CardBackground(prominence: prominence, radius: radius))
    }
}

/// Small uppercase section label.
struct Eyebrow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.caption2.weight(.semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Localizes text that comes from the core (display names, preset names), whose
/// English strings double as keys in the string tables.
extension Text {
    init(localizing key: String) {
        self.init(LocalizedStringKey(key))
    }
}
