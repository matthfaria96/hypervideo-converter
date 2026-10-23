import SwiftUI

/// The app's motion vocabulary. Every user action gets one of these curves, and
/// "Reduce Motion" turns all of them into a short crossfade.
enum Motion {
    /// Hover, press and other instant feedback.
    static let quick = Animation.smooth(duration: 0.18)
    /// Rows appearing, selection, tab and mode changes.
    static let standard = Animation.spring(duration: 0.38, bounce: 0.18)
    /// Banners, the inspector and other large elements.
    static let emphasized = Animation.spring(duration: 0.55, bounce: 0.26)
    /// Progress and numbers.
    static let snappy = Animation.snappy(duration: 0.25)
    /// What every curve becomes with Reduce Motion on.
    static let crossfade = Animation.linear(duration: 0.12)

    static func resolve(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        guard let animation else { return nil }
        return reduceMotion ? crossfade : animation
    }
}

extension AnyTransition {
    /// A row sliding into the list.
    static var rowInsert: AnyTransition { .move(edge: .top).combined(with: .opacity) }
    /// A row leaving the list.
    static var rowRemove: AnyTransition { .scale(scale: 0.96).combined(with: .opacity) }
    static var row: AnyTransition { .asymmetric(insertion: .rowInsert, removal: .rowRemove) }
    /// The body of a tab or a page replacing another.
    static var content: AnyTransition { .opacity.combined(with: .offset(y: 6)) }
    /// A banner dropping in from above.
    static var banner: AnyTransition { .move(edge: .top).combined(with: .opacity) }
    /// A card or panel that grows in place.
    static var pop: AnyTransition { .scale(scale: 0.97).combined(with: .opacity) }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct MotionTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

private struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered && !reduceMotion ? scale : 1)
            .onHover { hovered = $0 }
            .animation(Motion.resolve(Motion.quick, reduceMotion: reduceMotion), value: hovered)
    }
}

extension View {
    /// `animation(_:value:)` that honors Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation = Motion.standard, value: Value) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// `transition(_:)` that becomes a crossfade with Reduce Motion.
    func motionTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransition(transition: transition))
    }

    /// Lifts the view a touch while the pointer is over it.
    func hoverLift(_ scale: CGFloat = 1.01) -> some View {
        modifier(HoverLift(scale: scale))
    }
}
