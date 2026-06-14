import Foundation
import Observation

// The native file-explorer model (DESKTOP_APP_SPEC §7): a plain folder walk of
// the project, lazily loaded per directory. It shows everything on disk and
// applies NONE of the engine's tree-skip rules — that is the `tree` section's
// job, rendered by the engine, not here.
//
// A reference type so SwiftUI rows can lazily populate children on expansion
// without rebuilding the whole tree. `@Observable` so a row re-renders when its
// own `children` change — that's what lets an in-place reload surface a file
// added inside an already-expanded subfolder, not just at the root.
@Observable
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

    /// Re-read from disk every directory that's already been loaded, in place.
    /// New files appear, deleted ones drop, and surviving nodes keep their
    /// identity — so loaded subtrees and each row's expansion state are
    /// preserved, and the reload recurses into them. Collapsed (never-loaded)
    /// directories are left alone; they read fresh when first expanded.
    func reloadLoadedChildren() {
        guard isDirectory, let existing = children else { return }

        let byURL = Dictionary(existing.map { ($0.url, $0) }) { a, _ in a }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [])) ?? []

        let merged: [FileNode] = entries.map { child in
            if let kept = byURL[child] { return kept }   // reuse → keep subtree/state
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            return FileNode(url: child, isDirectory: isDir, projectRoot: projectRoot)
        }
        children = merged.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for child in merged { child.reloadLoadedChildren() }
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - Search

extension FileNode {
    /// Flat list of files (not folders) whose name matches `query`, walked from
    /// this node. Bounded so a pathological tree can't hang the UI. Used by the
    /// explorer's name search, which filters to a flat result list.
    /// Heavy/noise directories worth skipping when `skipNoise` is set (e.g. the
    /// in-app file picker), so the list isn't drowned in .git internals.
    private static let noiseDirs: Set<String> = [
        ".git", "node_modules", ".venv", "venv", "__pycache__", ".build",
        ".swiftpm", "dist", "build", ".mypy_cache", ".pytest_cache",
        ".ruff_cache", ".idea", ".vscode",
    ]

    static func searchFiles(root: URL, query: String, limit: Int = 500,
                            skipNoise: Bool = false) -> [FileNode] {
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
            if isDir {
                if skipNoise, noiseDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if needle.isEmpty || url.lastPathComponent.lowercased().contains(needle) {
                results.append(FileNode(url: url, isDirectory: false, projectRoot: root))
            }
        }
        return results.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    /// Flat list of directories (not files) whose name matches `query`, walked
    /// from this node. Noise dirs are pruned and never returned. Used by the
    /// folder-section picker to choose which folder to join.
    static func searchFolders(root: URL, query: String, limit: Int = 500) -> [FileNode] {
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
            guard isDir else { continue }
            if noiseDirs.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if needle.isEmpty || url.lastPathComponent.lowercased().contains(needle) {
                results.append(FileNode(url: url, isDirectory: true, projectRoot: root))
            }
        }
        return results.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }
}
