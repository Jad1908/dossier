import SwiftUI
import AppKit

// Reusable component treatments from DESIGN.md §Components. Views compose these
// rather than inlining fills, borders, or radii.

// MARK: - Surface / elevation modifiers

extension View {
    /// Level-1 hairline edge on a persistent surface (DESIGN.md §Elevation).
    func hairlineBorder(_ radius: CGFloat = Theme.Radius.md,
                        color: Color = Theme.Colors.hairline) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
    }

    /// A surface tile: fill + hairline + radius.
    func surfaceTile(fill: Color,
                     radius: CGFloat = Theme.Radius.md,
                     border: Color = Theme.Colors.hairline) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .hairlineBorder(radius, color: border)
    }

    /// Apply the design typography token (Inter + ss03 when available).
    func designFont(_ font: Font) -> some View {
        self.font(font)
    }
}

// MARK: - Buttons (DESIGN.md §Buttons)

/// The one cool-blue action — at most one per view.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(Theme.Colors.onAccent)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                configuration.isPressed
                    ? Theme.Colors.accentPrimaryPressed
                    : Theme.Colors.accentPrimary,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
            .pressable(configuration.isPressed)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
    @Environment(\.isEnabled) private var isEnabled
}

/// Transparent text button — lower emphasis (Save…, Cancel).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(isEnabled ? Theme.Colors.ink : Theme.Colors.ash)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(minHeight: 32)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .pressable(configuration.isPressed, scale: 0.96)
    }
}

/// Soft surface button — mid emphasis in-pane actions (Add Text, Add Tree).
struct TertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.button)
            .foregroundStyle(isEnabled ? Theme.Colors.ink : Theme.Colors.ash)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(minHeight: 32)
            .surfaceTile(fill: Theme.Colors.surfaceElevated)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .pressable(configuration.isPressed)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// A borderless icon button (the +/- affordances, drag handles, removes).
struct IconButtonStyle: ButtonStyle {
    var idleColor: Color = Theme.Colors.mute
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.Colors.ink : idleColor)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Chips & badges

/// Section-type label (tree / file / text).
struct TypeBadge: View {
    let kind: SectionKind
    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: kind.symbolName).imageScale(.small)
            Text(kind.label)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.mute)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
    }
}

enum StatusTone { case error, success, warning
    var solid: Color {
        switch self {
        case .error: return Theme.Colors.error
        case .success: return Theme.Colors.success
        case .warning: return Theme.Colors.warning
        }
    }
    var soft: Color {
        switch self {
        case .error: return Theme.Colors.errorSoft
        case .success: return Theme.Colors.successSoft
        case .warning: return Theme.Colors.warningSoft
        }
    }
}

struct StatusBadge: View {
    let tone: StatusTone
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(tone.solid)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tone.soft,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
    }
}

// MARK: - Keycap (DESIGN.md §keycap) — the only "physical depth" detail.

struct Keycap: View {
    let glyph: String
    init(_ glyph: String) { self.glyph = glyph }
    var body: some View {
        Text(glyph)
            .font(Theme.Typography.mono)
            .foregroundStyle(Theme.Colors.body)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .frame(minHeight: 18)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.keyBgStart, Theme.Colors.keyBgEnd],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
            )
            .hairlineBorder(Theme.Radius.xs, color: Theme.Colors.hairlineSoft)
    }
}
