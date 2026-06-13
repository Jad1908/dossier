import Foundation

// Locates the `dossier` binary and invokes `forge --format json` as a
// subprocess (DESKTOP_APP_SPEC §2, §8). The app never duplicates engine logic;
// rendering, tree-walking and token counting all stay in the engine.

enum EngineOutcome: Equatable {
    /// The engine produced JSON (which may itself report `ok: false`).
    case forged(ForgeResult)
    /// The engine could not run / produce JSON: missing binary, non-zero exit,
    /// unparseable output. Distinct from a spec-level error (§8, §10).
    case engineFailure(String)
}

struct Engine {
    /// Absolute path to the `dossier` executable.
    let binaryURL: URL

    // MARK: - Locating the binary

    /// Resolve the binary: an explicit override wins; otherwise probe a login
    /// shell's PATH and the usual install locations. A GUI app launched from
    /// Finder has a minimal PATH, so we cannot rely on `env` alone.
    static func locate(override: String?) -> Engine? {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return Engine(binaryURL: url)
            }
            return nil
        }
        if let viaShell = resolveViaLoginShell() {
            return Engine(binaryURL: viaShell)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/usr/local/bin/dossier",
            "/opt/homebrew/bin/dossier",
            home.appendingPathComponent(".local/bin/dossier").path,
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return Engine(binaryURL: URL(fileURLWithPath: path))
        }
        return nil
    }

    private static func resolveViaLoginShell() -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v dossier"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Running forge

    /// Run `dossier forge [name] --format json --root <root>` and parse the
    /// result. Blocking — call off the main thread (the AppModel does).
    /// How long a single render may take before we give up and terminate it.
    /// A render that needs longer (e.g. a `tree` section walking a huge,
    /// un-ignored directory like a build folder) would otherwise hang the UI.
    static let timeout: TimeInterval = 20

    /// - Parameter onStart: receives the live `Process` so the caller can
    ///   terminate it if a newer render supersedes this one.
    func forge(specName: String?, root: URL,
               onStart: ((Process) -> Void)? = nil) -> EngineOutcome {
        let process = Process()
        process.executableURL = binaryURL
        var args = ["forge"]
        if let specName, !specName.isEmpty { args.append(specName) }
        args += ["--format", "json", "--root", root.path]
        process.arguments = args

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .engineFailure("Could not launch dossier: \(error.localizedDescription)")
        }
        onStart?(process)

        // Watchdog: terminate the process if it outruns the timeout. `timedOut`
        // is set before terminating so we can report it distinctly.
        let timedOut = TimeoutFlag()
        let watchdog = DispatchWorkItem {
            if process.isRunning { timedOut.set(); process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: watchdog)

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if timedOut.value {
            return .engineFailure(
                "Render timed out after \(Int(Self.timeout))s. A tree section may "
                + "be walking a very large folder — re-enable “Respect .gitignore” "
                + "or add the folder to .dossier/config.toml’s [tree] exclude.")
        }

        // Non-zero exit is reserved for usage/argument errors before any JSON
        // (§3): treat it as an engine failure, surfacing stderr.
        if process.terminationStatus != 0 {
            let stderr = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? "exit code \(process.terminationStatus)" : stderr
            return .engineFailure(detail)
        }

        do {
            let result = try JSONDecoder().decode(ForgeResult.self, from: outData)
            return .forged(result)
        } catch {
            let raw = String(decoding: outData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = raw.isEmpty ? "(no output)" : String(raw.prefix(400))
            return .engineFailure("Could not parse engine output:\n\(snippet)")
        }
    }
}

/// A tiny lock-guarded bool, set on the watchdog queue and read on the worker.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
