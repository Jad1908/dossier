import SwiftUI

// An in-app folder picker shown in a popover (no system open panel): a search
// field over a scrollable list of the project's directories. Used to set or
// re-target a `folder` section. Returns the repo-relative path of the chosen
// folder. Mirrors FilePickerPopover, but lists directories rather than files.
struct FolderPickerPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    @State private var search = ""
    // Index of the keyboard-highlighted row in `folders`. Arrow keys move it,
    // Enter picks it; it stays at 0 (the top match) as the query changes.
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a folder")
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)

            SearchField(text: $search, placeholder: "Search folders", focus: $searchFocused)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                // Enter validates the highlighted match, so the keyboard alone can pick.
                .onSubmit { pickSelected() }

            Divider().overlay(Theme.Colors.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if folders.isEmpty {
                            Text("No folders")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.mute)
                                .padding(Theme.Spacing.md)
                        } else {
                            ForEach(Array(folders.enumerated()), id: \.element.id) { index, node in
                                FolderPickRow(node: node, selected: index == selection) {
                                    onPick(node.relativePath)
                                }
                                .id(node.id)
                            }
                        }
                    }
                    .padding(Theme.Spacing.xs)
                }
                .onChange(of: selection) { _, new in
                    guard folders.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(folders[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 340, height: 380)
        .background(Theme.Colors.surface)
        // Move the highlight with the arrow keys while focus stays in the
        // search field; clamp to the current result list.
        .onKeyPress(.downArrow) {
            guard !folders.isEmpty else { return .ignored }
            selection = min(selection + 1, folders.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !folders.isEmpty else { return .ignored }
            selection = max(selection - 1, 0)
            return .handled
        }
        // A changing query reshuffles results, so snap the highlight back to
        // the top match each time the text changes.
        .onChange(of: search) { selection = 0 }
        // Esc closes the picker. With the search field focused the popover
        // won't dismiss itself — the field editor swallows the cancel — so
        // catch the key on its way through the SwiftUI hierarchy.
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            // Focus the field after the popover settles so typing and arrow
            // navigation work immediately.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// Pick whichever row is highlighted, falling back to the top match.
    private func pickSelected() {
        guard !folders.isEmpty else { return }
        let index = folders.indices.contains(selection) ? selection : 0
        onPick(folders[index].relativePath)
    }

    private var folders: [FileNode] {
        guard let root = model.projectURL else { return [] }
        return FileNode.searchFolders(root: root, query: search)
    }
}

private struct FolderPickRow: View {
    let node: FileNode
    var selected: Bool = false
    let onPick: () -> Void
    @State private var hovering = false

    // Keyboard selection wins over hover so the highlight reads clearly while
    // arrow-navigating; hover keeps its subtler tint for the mouse.
    private var rowFill: Color {
        if selected { return Theme.Colors.accentSoft }
        return hovering ? Theme.Colors.hairlineSoft : Color.clear
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.mute)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .font(Theme.Typography.bodyMd)
                        .foregroundStyle(Theme.Colors.ink)
                        .lineLimit(1)
                    Text(node.relativePath)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowFill,
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
