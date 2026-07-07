import SwiftUI

// A reference card for the builder's keyboard shortcuts, opened with `?`.
// Jupyter-style single-key commands live in the builder pane and fire whenever
// the user isn't typing in a text field — the command/edit-mode split that
// BuilderView's AppKit key monitor enforces.
struct ShortcutsCheatSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: [String]
        let label: String
    }

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [Shortcut]
    }

    private let groups: [Group] = [
        Group(title: "Add sections", shortcuts: [
            Shortcut(keys: ["T"], label: "Add text section"),
            Shortcut(keys: ["⇧", "T"], label: "Add tree section"),
            Shortcut(keys: ["F"], label: "Add file section"),
            Shortcut(keys: ["⇧", "F"], label: "Add folder section"),
        ]),
        Group(title: "Navigate & select", shortcuts: [
            Shortcut(keys: ["↑"], label: "Select previous section"),
            Shortcut(keys: ["↓"], label: "Select next section"),
            Shortcut(keys: ["⇧", "↑/↓"], label: "Extend selection"),
        ]),
        Group(title: "Edit & reorder", shortcuts: [
            Shortcut(keys: ["↩"], label: "Edit selected section"),
            Shortcut(keys: ["⎋"], label: "Stop editing / clear selection"),
            Shortcut(keys: ["⌫"], label: "Delete selected section(s)"),
            Shortcut(keys: ["D", "D"], label: "Delete selected section(s)"),
            Shortcut(keys: ["⌘", "↑/↓"], label: "Move section up / down"),
            Shortcut(keys: ["⌃", "↑/↓"], label: "Move while editing"),
        ]),
        Group(title: "Other", shortcuts: [
            Shortcut(keys: ["?"], label: "Show this cheat sheet"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            Divider().overlay(Theme.Colors.hairline)
            footer
        }
        .frame(width: 460, height: 520)
        .background(Theme.Colors.surface)
    }

    private var header: some View {
        HStack {
            Text("Keyboard Shortcuts")
                .font(Theme.Typography.headingLg)
                .foregroundStyle(Theme.Colors.ink)
            Spacer()
            Text("Active when you're not typing in a field")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        }
        .padding(Theme.Spacing.lg)
    }

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(group.title.uppercased())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
            ForEach(group.shortcuts) { shortcut in
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { _, key in
                            keyCap(key)
                        }
                    }
                    .frame(width: 92, alignment: .leading)
                    Text(shortcut.label)
                        .font(Theme.Typography.bodyMd)
                        .foregroundStyle(Theme.Colors.ink)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(Theme.Typography.mono)
            .foregroundStyle(Theme.Colors.ink)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                    .fill(Theme.Colors.accentSoft))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Spacing.lg)
    }
}
