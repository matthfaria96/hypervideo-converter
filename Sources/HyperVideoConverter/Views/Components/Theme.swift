import SwiftUI

/// The app's dark palette (the window is always dark, like the design prototype).
enum Theme {
    static let background = Color(hex: 0x171719)
    static let sidebar = Color(hex: 0x1C1C1F)
    static let inspector = Color(hex: 0x1E1E21)
    static let panel = Color(hex: 0x222225)
    static let panelRaised = Color(hex: 0x29292D)
    static let control = Color(hex: 0x303034)
    static let line = Color(hex: 0x3A3A40)
    static let separator = Color(hex: 0x303034)
    static let text = Color(hex: 0xF5F5F7)
    static let muted = Color(hex: 0x9B9BA3)
    static let faint = Color(hex: 0x8E8E96)
    static let accent = Color(hex: 0xFFB52E)
    static let accentLight = Color(hex: 0xFFD071)
    static let accentText = Color(hex: 0x201809)
    static let accentWash = Color(hex: 0x3A3325)
    static let selectedCard = Color(hex: 0x332B1D)
    static let green = Color(hex: 0x65C98A)
    static let red = Color(hex: 0xFF8585)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The amber call-to-action button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(configuration.isPressed ? Theme.accentLight : Theme.accent, in: .rect(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(.rect)
    }
}

/// A quiet bordered button; `plain` drops the border, like the prototype's ghost buttons.
struct SubtleButtonStyle: ButtonStyle {
    var plain = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(plain ? Theme.muted : Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(background(configuration.isPressed), in: .rect(cornerRadius: 8))
            .overlay {
                if !plain { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line) }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.rect)
    }

    private func background(_ pressed: Bool) -> Color {
        if pressed { return Theme.line }
        return plain ? .clear : Theme.control
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
    static var ghost: SubtleButtonStyle { SubtleButtonStyle(plain: true) }
}

/// A rounded panel with a hairline border.
struct CardBackground: ViewModifier {
    var fill: Color = Theme.panel
    var radius: CGFloat = 11
    var stroke: Color = Theme.line

    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(stroke) }
    }
}

extension View {
    func card(fill: Color = Theme.panel, radius: CGFloat = 11, stroke: Color = Theme.line) -> some View {
        modifier(CardBackground(fill: fill, radius: radius, stroke: stroke))
    }
}

/// Small uppercase section label ("LIBRARY", "WORKSPACE").
struct Eyebrow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .bold))
            .kerning(1)
            .foregroundStyle(Theme.faint)
    }
}

/// Localizes text that comes from the core (display names, preset names), whose
/// English strings double as keys in the string tables.
extension Text {
    init(localizing key: String) {
        self.init(LocalizedStringKey(key))
    }
}
