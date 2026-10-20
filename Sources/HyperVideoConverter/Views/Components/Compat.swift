/// Compat.swift
///
/// Liquid Glass and some toolbar APIs only exist from macOS 26. These helpers use them
/// there and fall back to materials and classic styles on macOS 15.

import SwiftUI

/// Whether this Mac draws Liquid Glass (macOS 26+).
var supportsLiquidGlass: Bool {
    if #available(macOS 26, *) { return true }
    return false
}

enum CompatGlass {
    case regular
    case clear
}

extension View {
    /// `glassEffect` on macOS 26+, a material background before that.
    @ViewBuilder
    func compatGlass<S: Shape>(_ kind: CompatGlass = .regular, tint: Color? = nil,
                               interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26, *) {
            let base: Glass = kind == .clear ? .clear : .regular
            glassEffect((tint.map { base.tint($0) } ?? base).interactive(interactive), in: shape)
        } else {
            background(kind == .clear ? .ultraThinMaterial : .regularMaterial, in: shape)
                .background(tint ?? .clear, in: shape)
        }
    }

    /// `.buttonStyle(.glass)` on macOS 26+, `.bordered` before that.
    @ViewBuilder
    func compatGlassButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    /// `.buttonStyle(.glassProminent)` on macOS 26+, `.borderedProminent` before that.
    @ViewBuilder
    func compatGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }
}

extension ToolbarContent {
    /// `sharedBackgroundVisibility(.hidden)` on macOS 26+, unchanged before that.
    @ToolbarContentBuilder
    func compatHiddenSharedBackground() -> some ToolbarContent {
        if #available(macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
