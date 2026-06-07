import SwiftUI

// Left pane — the persistent IDE-style file explorer (DESKTOP_APP_SPEC §6, §7,
// DESIGN.md §file-explorer). A native folder walk; it shows everything on disk
// and applies none of the engine's tree-skip rules. It is the primary way
// `file` sections are created.
struct FileExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, placeholder: "Search files")
                .padding(Theme.Spacing.sm)

            Divider().overlay(Theme.Colors.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if let root = model.fileTreeRoot {
                        if search.isEmpty {
                            ForEach(root.childrenLoaded) { node in
                                FileNodeRow(node: node, depth: 0)
                            }
                        } else {
                            searchResults(root: root.url)
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
            }
        }
        .background(Theme.Colors.canvas)
    }

    @ViewBuilder
    private func searchResults(root: URL) -> some View {
        let matches = FileNode.searchFiles(root: root, query: search)
        if matches.isEmpty {
            Text("No matches")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
                .padding(Theme.Spacing.sm)
        } else {
            ForEach(matches) { node in
                FileRowContent(node: node, depth: 0, isFolder: false)
            }
        }
    }
}

// MARK: - Tree rows

private extension FileNode {
    /// Loads immediate children (idempotent) and returns them for display.
    var childrenLoaded: [FileNode] {
        loadChildrenIfNeeded()
        return children ?? []
    }
}

/// One row in the tree. Folders disclose recursively; files carry the +/- and
/// included state. Expansion is local view state.
struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    @State private var expanded = false

    var body: some View {
        if node.isDirectory {
            FileRowContent(node: node, depth: depth, isFolder: true,
                           expanded: expanded) {
                expanded.toggle()
            }
            if expanded {
                ForEach(node.childrenLoaded) { child in
                    FileNodeRow(node: child, depth: depth + 1)
                }
            }
        } else {
            FileRowContent(node: node, depth: depth, isFolder: false)
        }
    }
}

/// The visual content of one explorer row (DESIGN.md §file-tree-row).
struct FileRowContent: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    let depth: Int
    let isFolder: Bool
    var expanded: Bool = false
    var toggle: (() -> Void)? = nil
    @State private var hovering = false

    private var included: Bool {
        !isFolder && model.spec.referencedFilePaths.contains(node.relativePath)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // Indentation + disclosure chevron for folders.
            if isFolder {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.mute)
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 12)
            }

            Image(systemName: isFolder ? "folder" : "doc")
                .imageScale(.small)
                .foregroundStyle(included ? Theme.Colors.accentText : Theme.Colors.mute)

            Text(node.name)
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(included ? Theme.Colors.accentText : Theme.Colors.body)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.Spacing.xs)

            // +/- affordance — files only (folders never map to sections, §7).
            if !isFolder, hovering || included {
                Button {
                    model.toggleFile(relativePath: node.relativePath)
                } label: {
                    Image(systemName: included ? "minus.circle.fill" : "plus.circle")
                        .imageScale(.small)
                }
                .buttonStyle(IconButtonStyle(
                    idleColor: included ? Theme.Colors.accentText : Theme.Colors.mute))
                .help(included ? "Remove from prompt" : "Add to prompt")
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.leading, CGFloat(depth) * Theme.Spacing.md)
        .background(
            included ? Theme.Colors.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if isFolder { toggle?() }
            else { model.toggleFile(relativePath: node.relativePath) }
        }
        // Files are drag sources for the builder (multi-file drop adds one
        // `file` section each); the payload is the repo-relative path.
        .if(!isFolder) { view in
            view.draggable(node.relativePath) {
                Label(node.name, systemImage: "doc")
                    .padding(Theme.Spacing.xs)
            }
        }
    }
}

// MARK: - Search field (DESIGN.md §search-field)

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Theme.Colors.mute)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").imageScale(.small)
                }
                .buttonStyle(IconButtonStyle())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .surfaceTile(fill: Theme.Colors.surfaceElevated)
    }
}

// MARK: - Conditional modifier helper

extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool,
                                 transform: (Self) -> Transformed) -> some View {
        if condition { transform(self) } else { self }
    }
}
