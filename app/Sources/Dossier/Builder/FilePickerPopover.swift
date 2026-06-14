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

            SearchField(text: $search, placeholder: "Search files")
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            Divider().overlay(Theme.Colors.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if files.isEmpty {
                        Text("No files")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.mute)
                            .padding(Theme.Spacing.md)
                    } else {
                        ForEach(files) { node in
                            FilePickRow(node: node) { onPick(node.relativePath) }
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
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
    let onPick: () -> Void
    @State private var hovering = false

    private var included: Bool {
        model.spec.referencedFilePaths.contains(node.relativePath)
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
                hovering ? Theme.Colors.hairlineSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
