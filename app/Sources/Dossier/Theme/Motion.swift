import SwiftUI

// Motion tokens — one organic spring vocabulary, referenced everywhere so the
// app moves with a single consistent feel rather than ad-hoc per-view curves.
// DESIGN.md leaves motion to "platform convention"; these stay subtle and
// spring-based (no linear/ease ramps) so nothing feels mechanical.
extension Theme {
    enum Motion {
        /// Quick, tactile — hovers, +/- affordances, button presses.
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
        /// The workhorse — selection, layout, disclosure, mode switches.
        static let smooth = Animation.spring(response: 0.38, dampingFraction: 0.86)
        /// Calm — large surfaces, empty-state and banner entrances.
        static let gentle = Animation.spring(response: 0.52, dampingFraction: 0.90)
        /// A little life — section add/remove, "Copied" confirmation.
        static let bouncy = Animation.spring(response: 0.40, dampingFraction: 0.70)
    }
}

extension View {
    /// A gentle press-scale used by interactive rows/cards for a tactile feel.
    func pressable(_ pressed: Bool, scale: CGFloat = 0.97) -> some View {
        scaleEffect(pressed ? scale : 1)
            .animation(Theme.Motion.snappy, value: pressed)
    }
}
