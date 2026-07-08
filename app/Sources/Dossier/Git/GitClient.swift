import Foundation

// Talks to the project's git repository by shelling out to the system git —
// the same stance as Engine: the app owns no domain logic, it only shows what
// the tool reports. Every call here is blocking; run them off the main thread
// (AppModel wraps each in a detached task).

/// One branch in the switcher. Remote branches keep their remote-qualified
/// short name ("origin/main"); `localName` is what checking one out uses or
/// creates.
struct GitBranch: Hashable, Identifiable {
    let name: String
    let isRemote: Bool
    var id: String { (isRemote ? "remote:" : "local:") + name }

    /// "origin/feature/x" → "feature/x"; local names pass through unchanged.
    var localName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

/// What the branch bar shows: where HEAD is, where it could move to, and
/// whether the working tree has uncommitted changes.
struct GitSnapshot: Equatable {
    var currentBranch: String?      // nil when HEAD is detached
    var detachedHEAD: String?       // short SHA shown instead while detached
    var localBranches: [GitBranch] = []
    var remoteBranches: [GitBranch] = []
    var isDirty = false

    var displayName: String {
        currentBranch ?? detachedHEAD.map { "\($0) (detached)" } ?? "(no branch)"
    }
}

enum GitClient {
    /// The macOS git shim — present on every install. When the developer tools
    /// it fronts are missing it exits non-zero, `snapshot` returns nil, and the
    /// branch bar simply stays hidden.
    private static let gitPath = "/usr/bin/git"

    /// Read the repo state for `root`, or nil when it isn't inside a git work
    /// tree (or git itself can't run). `-C root` lets git find the enclosing
    /// repo, so opening a subfolder of a repo still gets its branches.
    static func snapshot(at root: URL) -> GitSnapshot? {
        guard runGit(["rev-parse", "--is-inside-work-tree"], at: root)?.stdout == "true"
        else { return nil }

        var snap = GitSnapshot()
        if let head = runGit(["branch", "--show-current"], at: root)?.stdout, !head.isEmpty {
            snap.currentBranch = head
        } else {
            snap.detachedHEAD = runGit(["rev-parse", "--short", "HEAD"], at: root)?.stdout
        }
        // Most recently committed first, so the branches actually being
        // juggled float to the top — VS Code's default sort order.
        if let out = runGit(["for-each-ref", "--format=%(refname:short)",
                             "--sort=-committerdate", "refs/heads"], at: root)?.stdout {
            snap.localBranches = out.split(separator: "\n")
                .map { GitBranch(name: String($0), isRemote: false) }
        }
        if let out = runGit(["for-each-ref", "--format=%(refname:short)",
                             "--sort=-committerdate", "refs/remotes"], at: root)?.stdout {
            snap.remoteBranches = out.split(separator: "\n")
                .filter { !$0.hasSuffix("/HEAD") }   // the symbolic default-branch pointer
                .map { GitBranch(name: String($0), isRemote: true) }
        }
        // --no-optional-locks: a plain `git status` opportunistically refreshes
        // the index, WRITING under .git — which fires the project file watcher,
        // which schedules another snapshot: an endless refresh storm. The flag
        // (also what VS Code uses) makes status read-only.
        snap.isDirty = runGit(["--no-optional-locks", "status", "--porcelain"],
                              at: root)?.stdout.isEmpty == false
        return snap
    }

    /// Check out `branch`. Picking a remote branch with no local counterpart
    /// creates one tracking it — the VS Code behavior. Returns a failure
    /// message (git's stderr) or nil on success.
    static func checkout(_ branch: GitBranch, at root: URL) -> String? {
        let args: [String]
        if branch.isRemote,
           runGit(["rev-parse", "--verify", "--quiet",
                   "refs/heads/\(branch.localName)"], at: root)?.status != 0 {
            args = ["checkout", "-b", branch.localName, "--track", branch.name]
        } else {
            args = ["checkout", branch.localName]
        }
        return failureMessage(runGit(args, at: root))
    }

    /// Create `name` at HEAD and switch to it. Returns a failure message or nil.
    static func createBranch(named name: String, at root: URL) -> String? {
        failureMessage(runGit(["checkout", "-b", name], at: root))
    }

    private static func failureMessage(_ result: GitRunResult?) -> String? {
        guard let result else { return "git could not be launched." }
        guard result.status != 0 else { return nil }
        return result.stderr.isEmpty ? "git exited with code \(result.status)." : result.stderr
    }

    private typealias GitRunResult = (status: Int32, stdout: String, stderr: String)

    private static func runGit(_ args: [String], at root: URL) -> GitRunResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", root.path] + args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: outData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
