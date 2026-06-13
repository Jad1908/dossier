import Foundation

// Swift mirror of the engine's pydantic spec schema (DESKTOP_APP_SPEC §5).
// Kept in sync with src/dossier/spec.py and config.py by hand. The contract
// test (tests/test_forge_json.py) guards the JSON these feed into.

// MARK: - Sections

/// A text section's body comes from exactly one source: an inline body, or a
/// named prompt resolved from .dossier/config.toml's [prompts]. The enum makes the
/// "exactly one" rule (spec.py TextSection) unrepresentable to violate.
enum TextSource: Equatable, Hashable {
    case body(String)
    case prompt(String)   // prompt name
}

/// One of the engine's four section kinds. The per-section fields match the
/// engine exactly: tree carries only max_depth + use_gitignore (include/exclude
/// live in .dossier/config.toml's [tree], not here — the engine forbids extra fields).
enum SectionKind: Equatable, Hashable {
    case tree(maxDepth: Int, useGitignore: Bool)
    case file(path: String)
    case text(source: TextSource)
    /// A csv head extractor (spec.py CsvSection): header + the first `rows`
    /// data rows (-1 = whole file), narrowed to `columns` when non-empty.
    case csv(path: String, rows: Int, columns: [String])
    /// A folder join (spec.py FolderSection): every file under `path`, each
    /// under a subheader with its path relative to the folder. csv files use
    /// the head extractor's defaults; binary files contribute a subheader only.
    case folder(path: String, useGitignore: Bool)

    /// The default peek for a freshly selected csv file.
    static let defaultCSVRows = 5

    /// The kind a newly selected file maps to: .csv files get the head
    /// extractor (first rows only); everything else inlines whole.
    static func forNewFile(relativePath: String) -> SectionKind {
        relativePath.lowercased().hasSuffix(".csv")
            ? .csv(path: relativePath, rows: defaultCSVRows, columns: [])
            : .file(path: relativePath)
    }

    var typeString: String {
        switch self {
        case .tree:   return "tree"
        case .file:   return "file"
        case .text:   return "text"
        case .csv:    return "csv"
        case .folder: return "folder"
        }
    }

    var label: String { typeString }

    var symbolName: String {
        switch self {
        case .tree:   return "list.bullet.indent"
        case .file:   return "doc.text"
        case .text:   return "text.alignleft"
        case .csv:    return "tablecells"
        case .folder: return "folder"
        }
    }
}

/// One spec section. `id` is app-local (TOML has no id); ordering is array order.
struct SpecSection: Identifiable, Equatable, Hashable {
    let id: UUID
    var title: String
    var kind: SectionKind

    init(id: UUID = UUID(), title: String, kind: SectionKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    /// The repo-relative path, for `file` and `csv` sections — the kinds the
    /// explorer's included state and dedupe key off.
    var filePath: String? {
        switch kind {
        case let .file(path): return path
        case let .csv(path, _, _): return path
        default: return nil
        }
    }
}

// MARK: - Output settings (spec.py OutputConfig)

struct OutputSettings: Equatable, Hashable {
    var copy: Bool = true
    var stdout: Bool = true
    var file: String = ""
}

// MARK: - Spec (a context.toml)

struct Spec: Equatable {
    /// Optional per-spec [output] block; nil when absent so its set fields merge
    /// correctly against project config (matches the engine's None handling).
    var output: OutputSettings?
    var sections: [SpecSection]

    init(output: OutputSettings? = nil, sections: [SpecSection] = []) {
        self.output = output
        self.sections = sections
    }

    /// The starter spec `dossier init` writes — used when creating a new spec.
    static var starter: Spec {
        Spec(
            output: OutputSettings(copy: true, stdout: true, file: ""),
            sections: [
                SpecSection(title: "PROJECT STRUCTURE",
                        kind: .tree(maxDepth: -1, useGitignore: true)),
                SpecSection(title: "REQUEST",
                        kind: .text(source: .body(
                            "Describe what you want the assistant to do here."))),
            ]
        )
    }

    /// Set of repo-relative paths referenced by `file` sections — the explorer's
    /// "included" derivation (DESKTOP_APP_SPEC §6).
    var referencedFilePaths: Set<String> {
        Set(sections.compactMap(\.filePath))
    }
}

// MARK: - Project config (a .dossier/config.toml — config.py DossierConfig)

struct ProjectConfig: Equatable {
    var output: OutputSettings?
    var treeExclude: [String]
    var treeInclude: [String]
    var prompts: [String: String]

    init(output: OutputSettings? = nil,
         treeExclude: [String] = [],
         treeInclude: [String] = [],
         prompts: [String: String] = [:]) {
        self.output = output
        self.treeExclude = treeExclude
        self.treeInclude = treeInclude
        self.prompts = prompts
    }

    var promptNames: [String] { prompts.keys.sorted() }
}
