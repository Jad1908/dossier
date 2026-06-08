import SwiftUI

// An in-app file picker shown in a popover (no system open panel): a search
// field over a scrollable list of the project's files. Used to set or re-target
// a `file` section. Returns the repo-relative path of the chosen file.
struct FilePickerPopover: View {
    @Environment(AppModel.self) private var model
    let onPick: (String) -> Void

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
        }
        .frame(width: 340, height: 380)
        .background(Theme.Colors.surface)
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
