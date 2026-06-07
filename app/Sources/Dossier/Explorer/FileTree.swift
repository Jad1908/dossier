import Foundation

// The native file-explorer model (DESKTOP_APP_SPEC §7): a plain folder walk of
// the project, lazily loaded per directory. It shows everything on disk and
// applies NONE of the engine's tree-skip rules — that is the `tree` section's
// job, rendered by the engine, not here.
//
// A reference type so SwiftUI rows can lazily populate children on expansion
// without rebuilding the whole tree.
final class FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let projectRoot: URL
    private(set) var children: [FileNode]?   // nil until a directory is loaded

    init(url: URL, isDirectory: Bool, projectRoot: URL) {
        self.url = url
        self.isDirectory = isDirectory
        self.projectRoot = projectRoot
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// Path relative to the project root — the form a `file` section stores.
    var relativePath: String {
        let root = projectRoot.path.hasSuffix("/") ? projectRoot.path
            : projectRoot.path + "/"
        if url.path.hasPrefix(root) {
            return String(url.path.dropFirst(root.count))
        }
        return name
    }

    /// Load this directory's immediate children once. Folders first, then files,
    /// each alphabetical, case-insensitive. Dotfiles are shown (the explorer
    /// hides nothing — §7), but the on-disk noise dirs that no one wants to
    /// scroll past are not special-cased here; the tree is the raw folder.
    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let entries = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [])) ?? []
        let nodes: [FileNode] = entries.map { child in
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            return FileNode(url: child, isDirectory: isDir, projectRoot: projectRoot)
        }
        children = nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Force a reload of children (e.g. after files change on disk).
    func reload() {
        children = nil
        loadChildrenIfNeeded()
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - Search

extension FileNode {
    /// Flat list of files (not folders) whose name matches `query`, walked from
    /// this node. Bounded so a pathological tree can't hang the UI. Used by the
    /// explorer's name search, which filters to a flat result list.
    static func searchFiles(root: URL, query: String, limit: Int = 500) -> [FileNode] {
        let needle = query.lowercased()
        var results: [FileNode] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []) else { return [] }

        for case let url as URL in enumerator {
            if results.count >= limit { break }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDir { continue }
            if url.lastPathComponent.lowercased().contains(needle) {
                results.append(FileNode(url: url, isDirectory: false, projectRoot: root))
            }
        }
        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
