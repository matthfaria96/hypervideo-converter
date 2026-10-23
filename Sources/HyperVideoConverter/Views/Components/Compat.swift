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

    /// `.buttonStyle(.glassProminent)` on macOS 26+, `.borderedProminent` before that,
    /// filled with the app's accent (prominent glass doesn't inherit the window tint).
    @ViewBuilder
    func compatGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }

    /// The bar at the bottom of the workspace: the window's bar material, which the
    /// system renders as glass on macOS 26+.
    func compatBarBackground() -> some View {
        background(.bar)
    }

    /// Soft scroll-edge fading under toolbars on macOS 26+; nothing before that.
    @ViewBuilder
    func compatSoftScrollEdges() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }

    /// A bar pinned to the bottom edge. On macOS 26+ it's a safe-area bar, so the scroll
    /// view under it fades and blurs its content instead of showing it through the glass.
    @ViewBuilder
    func compatBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        }
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
