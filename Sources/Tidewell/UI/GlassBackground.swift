import SwiftUI

/// macOS 26's Liquid Glass, where it exists.
///
/// Applied through a modifier rather than inline `if #available` so the fallback is
/// written once and every surface gets the same treatment. On Sonoma and Sequoia the
/// fallback is a real material, not a disabled-looking flat panel — a gated feature needs
/// a fallback that looks intentional, not absent.
struct GlassPanel: ViewModifier {

    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, a material below it.
    func glassPanel(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// Honour Reduce Motion by removing animation rather than shortening it.
    ///
    /// A user who asks for less motion is often asking because motion makes them unwell;
    /// a faster animation is still an animation.
    func gentleAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(GentleAnimation(value: value))
    }
}

private struct GentleAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: value)
    }
}
