import Foundation
import TOMLKit

// Reads and writes .dossier/context.toml / context.<name>.toml and config.toml using a
// Swift TOML library (DESKTOP_APP_SPEC §2). The engine remains the reader at
// render time; this is the editor side.
//
// Accepted trade-off (§2): writing reserializes the TOML and loses hand-written
// comments. App-managed specs are app-managed.
enum SpecIO {

    enum IOError: LocalizedError {
        case parse(String)
        var errorDescription: String? {
            switch self { case let .parse(m): return m }
        }
    }

    // MARK: - Spec (context.toml)

    static func loadSpec(at url: URL) throws -> Spec {
        let text = try String(contentsOf: url, encoding: .utf8)
        let table: TOMLTable
        do { table = try TOMLTable(string: text) }
        catch { throw IOError.parse("invalid TOML in \(url.lastPathComponent): \(error)") }

        var output: OutputSettings?
        if let out = table["output"]?.table {
            output = OutputSettings(
                copy: out["copy"]?.bool ?? true,
                stdout: out["stdout"]?.bool ?? true,
                file: out["file"]?.string ?? ""
            )
        }

        var sections: [SpecSection] = []
        if let arr = table["section"]?.array {
            for value in arr {
                guard let t = value.table else { continue }
                let title = t["title"]?.string ?? ""
                switch t["type"]?.string {
                case "tree":
                    sections.append(SpecSection(title: title, kind: .tree(
                        maxDepth: t["max_depth"]?.int ?? -1,
                        useGitignore: t["use_gitignore"]?.bool ?? true)))
                case "file":
                    sections.append(SpecSection(title: title,
                        kind: .file(path: t["path"]?.string ?? "",
                                    external: t["external"]?.bool ?? false)))
                case "csv":
                    sections.append(SpecSection(title: title, kind: .csv(
                        path: t["path"]?.string ?? "",
                        rows: t["rows"]?.int ?? SectionKind.defaultCSVRows,
                        columns: (t["columns"]?.array).map(strings) ?? [],
                        external: t["external"]?.bool ?? false)))
                case "folder":
                    sections.append(SpecSection(title: title, kind: .folder(
                        path: t["path"]?.string ?? "",
                        useGitignore: t["use_gitignore"]?.bool ?? true)))
                case "text":
                    if let prompt = t["prompt"]?.string {
                        sections.append(SpecSection(title: title,
                            kind: .text(source: .prompt(prompt))))
                    } else {
                        sections.append(SpecSection(title: title,
                            kind: .text(source: .body(t["body"]?.string ?? ""))))
                    }
                default:
                    continue   // unknown type — the engine reports it on render
                }
            }
        }
        return Spec(output: output, sections: sections)
    }

    static func writeSpec(_ spec: Spec, to url: URL) throws {
        let root = TOMLTable()

        if let out = spec.output {
            let o = TOMLTable()
            o["copy"] = out.copy
            o["stdout"] = out.stdout
            o["file"] = out.file
            root["output"] = o
        }

        let arr = TOMLArray()
        for section in spec.sections {
            let t = TOMLTable()
            t["type"] = section.kind.typeString
            t["title"] = section.title
            switch section.kind {
            case let .tree(maxDepth, useGitignore):
                t["max_depth"] = maxDepth
                t["use_gitignore"] = useGitignore
            case let .file(path, external):
                t["path"] = path
                if external { t["external"] = true }
            case let .csv(path, rows, columns, external):
                t["path"] = path
                t["rows"] = rows
                if !columns.isEmpty {
                    let a = TOMLArray(); columns.forEach { a.append($0) }
                    t["columns"] = a
                }
                if external { t["external"] = true }
            case let .folder(path, useGitignore):
                t["path"] = path
                t["use_gitignore"] = useGitignore
            case let .text(source):
                switch source {
                case let .body(body): t["body"] = body
                case let .prompt(name): t["prompt"] = name
                }
            }
            arr.append(t)
        }
        root["section"] = arr

        try write(root, to: url)
    }

    // MARK: - Project config (.dossier/config.toml)

    static func loadConfig(at url: URL) throws -> ProjectConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectConfig()
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let table: TOMLTable
        do { table = try TOMLTable(string: text) }
        catch { throw IOError.parse("invalid TOML in \(url.lastPathComponent): \(error)") }

        var output: OutputSettings?
        if let out = table["output"]?.table {
            output = OutputSettings(
                copy: out["copy"]?.bool ?? true,
                stdout: out["stdout"]?.bool ?? true,
                file: out["file"]?.string ?? "")
        }

        var exclude: [String] = [], include: [String] = []
        if let tree = table["tree"]?.table {
            exclude = (tree["exclude"]?.array).map(strings) ?? []
            include = (tree["include"]?.array).map(strings) ?? []
        }

        var prompts: [String: String] = [:]
        if let pt = table["prompts"]?.table {
            for key in pt.keys {
                if let v = pt[key]?.string { prompts[key] = v }
            }
        }

        return ProjectConfig(output: output, treeExclude: exclude,
                             treeInclude: include, prompts: prompts)
    }

    static func writeConfig(_ config: ProjectConfig, to url: URL) throws {
        let root = TOMLTable()

        if let out = config.output {
            let o = TOMLTable()
            o["copy"] = out.copy
            o["stdout"] = out.stdout
            o["file"] = out.file
            root["output"] = o
        }

        if !config.treeExclude.isEmpty || !config.treeInclude.isEmpty {
            let tree = TOMLTable()
            if !config.treeExclude.isEmpty {
                let a = TOMLArray(); config.treeExclude.forEach { a.append($0) }
                tree["exclude"] = a
            }
            if !config.treeInclude.isEmpty {
                let a = TOMLArray(); config.treeInclude.forEach { a.append($0) }
                tree["include"] = a
            }
            root["tree"] = tree
        }

        if !config.prompts.isEmpty {
            let pt = TOMLTable()
            for (key, value) in config.prompts { pt[key] = value }
            root["prompts"] = pt
        }

        try write(root, to: url)
    }

    // MARK: - Helpers

    private static func strings(_ array: TOMLArray) -> [String] {
        array.compactMap { $0.string }
    }

    private static func write(_ table: TOMLTable, to url: URL) throws {
        // Specs and config live in a `.dossier/` folder that may not exist yet.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let text = table.convert(to: .toml, options: [.allowMultilineStrings])
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
