import SwiftUI
import AppKit

// The single SwiftUI encoding of DESIGN.md. Views reference these tokens only —
// no ad-hoc hex values or magic numbers anywhere else in the app.
//
// Every color is mode-aware: it resolves to its Light or Dark value at runtime
// from the system appearance, via a dynamic NSColor provider (DESIGN.md §Colors).
enum Theme {

    // MARK: - Color tokens (DESIGN.md §Colors)

    enum Colors {
        // Brand & accent — teal (DESIGN.md §Brand & Accent).
        static let accentPrimary        = dyn(light: 0x0C6B61, dark: 0x0D9488)
        static let accentPrimaryPressed = dyn(light: 0x0A564E, dark: 0x0B7D72)
        static let onAccent             = dyn(light: 0xFFFFFF, dark: 0xFFFFFF)
        static let accentText           = dyn(light: 0x0C6B61, dark: 0x2DD4BF)
        static let accentSoft           = dyn(light: 0x0C6B61, lightAlpha: 0.10,
                                               dark: 0x0D9488, darkAlpha: 0.18)

        // Surface ladder — dark rises lighter; light compresses toward white.
        static let canvas          = dyn(light: 0xF4F6F9, dark: 0x08090C)
        static let surface         = dyn(light: 0xFCFDFE, dark: 0x0D0F14)
        static let surfaceElevated = dyn(light: 0xFFFFFF, dark: 0x12141B)
        static let surfaceCard     = dyn(light: 0xFFFFFF, dark: 0x171922)

        // Borders
        static let hairline       = dyn(light: 0xE3E6EC, dark: 0x25282F)
        static let hairlineStrong = dyn(light: 0x000000, lightAlpha: 0.14,
                                         dark: 0xFFFFFF, darkAlpha: 0.16)
        static let hairlineSoft   = dyn(light: 0x000000, lightAlpha: 0.06,
                                         dark: 0xFFFFFF, darkAlpha: 0.08)

        // Text / ink ladder
        static let ink   = dyn(light: 0x0E1116, dark: 0xF3F4F7)
        static let body  = dyn(light: 0x3A3F47, dark: 0xC9CCD3)
        static let mute  = dyn(light: 0x6B7079, dark: 0x969AA4)
        static let ash   = dyn(light: 0x9AA0A8, dark: 0x696D77)
        static let stone = dyn(light: 0xC2C7CE, dark: 0x43464E)

        // Status (semantic) — reserved for state, never chrome.
        static let error       = dyn(light: 0xD93A45, dark: 0xFF6B6B)
        static let errorSoft   = dyn(light: 0xD93A45, lightAlpha: 0.10,
                                     dark: 0xFF6B6B, darkAlpha: 0.16)
        static let success     = dyn(light: 0x1F9A63, dark: 0x5FD49B)
        static let successSoft = dyn(light: 0x1F9A63, lightAlpha: 0.10,
                                     dark: 0x5FD49B, darkAlpha: 0.16)
        static let warning     = dyn(light: 0xB7791F, dark: 0xFFC94D)
        static let warningSoft = dyn(light: 0xB7791F, lightAlpha: 0.10,
                                     dark: 0xFFC94D, darkAlpha: 0.16)

        // Keycap gradient — the only gradient in the system.
        static let keyBgStart = dyn(light: 0xFFFFFF, dark: 0x1B1D26)
        static let keyBgEnd   = dyn(light: 0xF1F3F6, dark: 0x0F1116)
    }

    // MARK: - Spacing (DESIGN.md §Layout — 8px base)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner radii (DESIGN.md §Shapes)

    enum Radius {
        static let none: CGFloat = 0
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 6
        static let md:   CGFloat = 8
        static let lg:   CGFloat = 10
        static let xl:   CGFloat = 16
        static let full: CGFloat = 9999
    }

    // MARK: - Typography (DESIGN.md §Typography)
    //
    // Inter is bundled if present; otherwise the system face stands in (it also
    // carries the macOS control conventions the sizes are tuned to). `ss03` is
    // applied via the font-feature API when Inter is available.

    enum Typography {
        static let display     = font(32, .semibold)
        static let headingLg   = font(22, .medium)
        static let headingMd   = font(17, .medium)
        static let headingSm   = font(15, .medium)
        static let bodyMd      = font(13, .regular)
        static let bodyStrong  = font(13, .medium)
        static let caption     = font(11, .regular)
        static let button      = font(13, .medium)
        // The monospace face — used ONLY for the rendered-prompt preview and keycaps.
        static let mono        = Font.system(size: 12, weight: .regular, design: .monospaced)

        private static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
            if NSFont(name: "Inter", size: size) != nil {
                return .custom("Inter", size: size).weight(weight)
            }
            return .system(size: size, weight: weight)
        }
    }
}

// MARK: - Dynamic color construction

private extension Theme {
    static func dyn(light: Int, dark: Int) -> Color {
        dyn(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    static func dyn(light: Int, lightAlpha: CGFloat,
                    dark: Int, darkAlpha: CGFloat) -> Color {
        let ns = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? nsColor(hex: dark, alpha: darkAlpha)
                : nsColor(hex: light, alpha: lightAlpha)
        }
        return Color(nsColor: ns)
    }

    static func nsColor(hex: Int, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue:    CGFloat(hex & 0xFF) / 255.0,
            alpha:   alpha
        )
    }
}
