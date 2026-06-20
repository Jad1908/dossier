import SwiftUI

// An in-app file picker shown in a popover: a search field over a scrollable
// list of the project's files, with an escape hatch to the system open panel
// for files outside the project. Used to set or re-target a `file` section.
// `onPick` receives a repo-relative path; `onPickExternal` (when provided)
// receives the absolute path of a file chosen from anywhere on disk.
struct FilePickerPopover: View {
    @Environment(AppModel.self) private var model
    let onPick: (String) -> Void
    var onPickExternal: ((String) -> Void)? = nil

    @State private var search = ""
    // Index of the keyboard-highlighted row in `files`. Arrow keys move it,
    // Enter picks it; it stays at 0 (the top match) as the query changes.
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a file")
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)

            SearchField(text: $search, placeholder: "Search files", focus: $searchFocused)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                // Enter validates the highlighted match, so the keyboard alone can pick.
                .onSubmit { pickSelected() }

            Divider().overlay(Theme.Colors.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if files.isEmpty {
                            Text("No files")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.mute)
                                .padding(Theme.Spacing.md)
                        } else {
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, node in
                                FilePickRow(node: node, selected: index == selection) {
                                    onPick(node.relativePath)
                                }
                                .id(node.id)
                            }
                        }
                    }
                    .padding(Theme.Spacing.xs)
                }
                .onChange(of: selection) { _, new in
                    guard files.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(files[new].id, anchor: .center)
                    }
                }
            }

            if let onPickExternal {
                Divider().overlay(Theme.Colors.hairline)
                Button(action: { chooseFromDisk(onPickExternal) }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "folder.badge.plus").imageScale(.small)
                        Text("Choose from disk…")
                            .font(Theme.Typography.bodyMd)
                        Spacer()
                    }
                    .foregroundStyle(Theme.Colors.accentText)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Join a file from anywhere on disk, outside this project")
            }
        }
        .frame(width: 340, height: 380)
        .background(Theme.Colors.surface)
        // Move the highlight with the arrow keys while focus stays in the
        // search field; clamp to the current result list.
        .onKeyPress(.downArrow) {
            guard !files.isEmpty else { return .ignored }
            selection = min(selection + 1, files.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !files.isEmpty else { return .ignored }
            selection = max(selection - 1, 0)
            return .handled
        }
        // A changing query reshuffles results, so snap the highlight back to
        // the top match each time the text changes.
        .onChange(of: search) { selection = 0 }
        .onAppear {
            // Focus the field after the popover settles so typing and arrow
            // navigation work immediately.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// Pick whichever row is highlighted, falling back to the top match.
    private func pickSelected() {
        guard !files.isEmpty else { return }
        let index = files.indices.contains(selection) ? selection : 0
        onPick(files[index].relativePath)
    }

    /// Open the system panel and hand back the absolute path of the chosen file.
    /// External files live outside the project, so the engine reads them by
    /// absolute path (the section is flagged `external`).
    private func chooseFromDisk(_ onPick: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Join"
        panel.message = "Choose a file to join from outside the project"
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url.path)
        }
    }

    private var files: [FileNode] {
        guard let root = model.projectURL else { return [] }
        return FileNode.searchFiles(root: root, query: search, skipNoise: true)
    }
}

private struct FilePickRow: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    var selected: Bool = false
    let onPick: () -> Void
    @State private var hovering = false

    private var included: Bool {
        model.spec.referencedFilePaths.contains(node.relativePath)
    }

    // Keyboard selection wins over hover so the highlight reads clearly while
    // arrow-navigating; hover keeps its subtler tint for the mouse.
    private var rowFill: Color {
        if selected { return Theme.Colors.accentSoft }
        return hovering ? Theme.Colors.hairlineSoft : Color.clear
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc")
                    .imageScale(.small)
                    .foregroundStyle(included ? Theme.Colors.accentText : Theme.Colors.mute)
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
                if included {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .foregroundStyle(Theme.Colors.accentText)
                }
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
