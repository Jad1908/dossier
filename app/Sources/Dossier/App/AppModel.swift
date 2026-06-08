import SwiftUI
import Observation

/// A spec in the open folder: nil name = the default context.toml; a name maps
/// to context.<name>.toml (DESKTOP_APP_SPEC §6).
struct SpecRef: Identifiable, Hashable {
    let name: String?
    var id: String { name ?? "" }
    var displayName: String { name ?? "context" }
    var fileName: String { name.map { "context.\($0).toml" } ?? "context.toml" }
}

/// The single source of truth for app state (DESKTOP_APP_SPEC §4: Observation).
/// Owns the open project, the loaded spec/config, the file tree, and the live
/// forge result. The engine is reached only via `Engine` (a subprocess).
@MainActor
@Observable
final class AppModel {

    // MARK: - Engine

    var engine: Engine?
    var enginePathOverride: String? = Defaults.enginePathOverride {
        didSet { Defaults.enginePathOverride = enginePathOverride; resolveEngine() }
    }
    var engineMissing: Bool { engine == nil }

    // MARK: - Project

    private(set) var projectURL: URL?
    private(set) var fileTreeRoot: FileNode?
    private(set) var availableSpecs: [SpecRef] = []
    var currentSpec = SpecRef(name: nil)

    // MARK: - Loaded documents

    var spec = Spec()
    var config = ProjectConfig()
    /// A spec/config load error (bad TOML) — distinct from a render error.
    private(set) var loadError: String?

    // MARK: - Builder selection

    var selectedSectionID: UUID?

    // MARK: - Render state

    private(set) var isRendering = false
    private(set) var lastResult: ForgeResult?
    private(set) var engineError: String?
    /// Transient "Copied" / "Saved" confirmation for the toolbar.
    var transientStatus: String?

    private var renderTask: Task<Void, Never>?

    init() {
        Defaults.registerDefaults()
        resolveEngine()
        reopenMostRecentProject()
    }

    /// Reopen the most recent project that still exists on launch — the usual
    /// IDE behavior, and a natural use of the remembered recents (§11). Falls
    /// through to the welcome empty state when there is none.
    private func reopenMostRecentProject() {
        guard Defaults.reopenLastProject else { return }
        if let recent = recentProjectURLs.first,
           FileManager.default.fileExists(atPath: recent.path) {
            openProject(recent)
        }
    }

    func resolveEngine() {
        engine = Engine.locate(override: enginePathOverride)
    }

    // MARK: - Opening a project

    var hasProject: Bool { projectURL != nil }

    func openProject(_ url: URL) {
        projectURL = url
        Defaults.noteRecentProject(url)
        fileTreeRoot = FileNode(url: url, isDirectory: true, projectRoot: url)
        fileTreeRoot?.loadChildrenIfNeeded()
        refreshSpecList()
        // Prefer the default spec if present, else the first discovered one.
        currentSpec = availableSpecs.first { $0.name == nil }
            ?? availableSpecs.first
            ?? SpecRef(name: nil)
        loadSpecAndConfig()
        render()
    }

    var recentProjectURLs: [URL] {
        Defaults.recentProjectPaths.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Spec discovery & switching

    func refreshSpecList() {
        guard let projectURL else { availableSpecs = []; return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: projectURL.path)) ?? []
        var refs: [SpecRef] = []
        for entry in entries {
            if entry == "context.toml" {
                refs.append(SpecRef(name: nil))
            } else if entry.hasPrefix("context."), entry.hasSuffix(".toml") {
                let middle = entry.dropFirst("context.".count).dropLast(".toml".count)
                if !middle.isEmpty { refs.append(SpecRef(name: String(middle))) }
            }
        }
        availableSpecs = refs.sorted {
            ($0.name ?? "") .localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    func specURL(for ref: SpecRef) -> URL? {
        projectURL?.appendingPathComponent(ref.fileName)
    }

    var configURL: URL? {
        projectURL?.appendingPathComponent("dossier.toml")
    }

    func switchSpec(to ref: SpecRef) {
        currentSpec = ref
        selectedSectionID = nil
        loadSpecAndConfig()
        render()
    }

    /// Section count for a spec on disk, for the management list. Best-effort:
    /// nil if the file can't be read/parsed.
    func sectionCount(for ref: SpecRef) -> Int? {
        guard let url = specURL(for: ref),
              FileManager.default.fileExists(atPath: url.path),
              let loaded = try? SpecIO.loadSpec(at: url) else { return nil }
        return loaded.sections.count
    }

    /// Delete a spec file from disk, then refresh and (if it was current) switch
    /// to another spec. Destructive — the caller confirms first.
    func deleteSpec(_ ref: SpecRef) {
        guard let url = specURL(for: ref) else { return }
        try? FileManager.default.removeItem(at: url)
        refreshSpecList()
        if currentSpec == ref {
            switchSpec(to: availableSpecs.first { $0.name == nil }
                ?? availableSpecs.first
                ?? SpecRef(name: nil))
        }
    }

    /// Create a new context.<name>.toml from the starter spec, then switch to it.
    func createSpec(named name: String?) {
        guard let projectURL else { return }
        let ref = SpecRef(name: name?.isEmpty == true ? nil : name)
        let url = projectURL.appendingPathComponent(ref.fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? SpecIO.writeSpec(.starter, to: url)
        }
        refreshSpecList()
        switchSpec(to: ref)
    }

    func loadSpecAndConfig() {
        loadError = nil
        guard let specURL = specURL(for: currentSpec), let configURL else { return }
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                config = try SpecIO.loadConfig(at: configURL)
            } else {
                config = ProjectConfig()
            }
        } catch {
            config = ProjectConfig()
            loadError = error.localizedDescription
        }
        if FileManager.default.fileExists(atPath: specURL.path) {
            do { spec = try SpecIO.loadSpec(at: specURL) }
            catch { spec = Spec(); loadError = error.localizedDescription }
        } else {
            spec = Spec()
        }
    }

    /// Does the current folder have the selected spec on disk?
    var currentSpecExists: Bool {
        guard let url = specURL(for: currentSpec) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func createCurrentSpec() {
        guard let url = specURL(for: currentSpec) else { return }
        try? SpecIO.writeSpec(.starter, to: url)
        refreshSpecList()
        loadSpecAndConfig()
        render()
    }

    // MARK: - File tree refresh

    func reloadFileTree() {
        fileTreeRoot?.reload()
    }

    // MARK: - SpecSection mutations (all autosave + re-render)

    /// Where a new section lands by default: right after the selected card, or
    /// at the end when nothing is selected. Each add then selects the new
    /// section, so a run of adds stays in order below the selection.
    private var defaultInsertIndex: Int {
        if let id = selectedSectionID,
           let i = spec.sections.firstIndex(where: { $0.id == id }) {
            return i + 1
        }
        return spec.sections.count
    }

    /// The index just after a specific section — used by the inline "+" between
    /// cards, which inserts there regardless of the current selection.
    func insertionIndex(after id: UUID) -> Int {
        if let i = spec.sections.firstIndex(where: { $0.id == id }) { return i + 1 }
        return spec.sections.count
    }

    private func insert(_ section: SpecSection, at index: Int?) {
        let clamped = min(max(index ?? defaultInsertIndex, 0), spec.sections.count)
        withAnimation(Theme.Motion.bouncy) {
            spec.sections.insert(section, at: clamped)
            selectedSectionID = section.id
        }
        scheduleSave()
    }

    func addFileSection(relativePath: String, at index: Int? = nil) {
        // Already in the prompt: select that card instead of adding a duplicate.
        if let existing = spec.sections.first(where: { $0.filePath == relativePath }) {
            selectedSectionID = existing.id
            return
        }
        let title = (relativePath as NSString).lastPathComponent.uppercased()
        insert(SpecSection(title: title, kind: .file(path: relativePath)), at: index)
    }

    func removeFileSection(relativePath: String) {
        withAnimation(Theme.Motion.smooth) {
            spec.sections.removeAll { $0.filePath == relativePath }
        }
        scheduleSave()
    }

    func toggleFile(relativePath: String) {
        if spec.referencedFilePaths.contains(relativePath) {
            removeFileSection(relativePath: relativePath)
        } else {
            addFileSection(relativePath: relativePath)
        }
    }

    /// Change which file a `file` section points at. Keeps a custom title, but
    /// refreshes a still-default (auto-derived) one to the new file's name.
    func setFileSection(_ id: UUID, relativePath: String) {
        guard let i = spec.sections.firstIndex(where: { $0.id == id }) else { return }
        var section = spec.sections[i]
        let oldDefault = (section.filePath as NSString?)?.lastPathComponent.uppercased()
        if section.title.isEmpty || section.title == oldDefault {
            section.title = (relativePath as NSString).lastPathComponent.uppercased()
        }
        section.kind = .file(path: relativePath)
        spec.sections[i] = section
        scheduleSave()
    }

    func addTextSection(at index: Int? = nil) {
        insert(SpecSection(title: "NEW SECTION", kind: .text(source: .body(""))),
               at: index)
    }

    func addTreeSection(at index: Int? = nil) {
        insert(SpecSection(title: "PROJECT STRUCTURE",
                           kind: .tree(maxDepth: -1, useGitignore: true)),
               at: index)
    }


    func removeSection(id: UUID) {
        withAnimation(Theme.Motion.smooth) {
            spec.sections.removeAll { $0.id == id }
            if selectedSectionID == id { selectedSectionID = nil }
        }
        scheduleSave()
    }

    func moveSections(from offsets: IndexSet, to destination: Int) {
        withAnimation(Theme.Motion.smooth) {
            spec.sections.move(fromOffsets: offsets, toOffset: destination)
        }
        scheduleSave()
    }

    /// A binding to one section that re-renders on edit.
    func binding(for id: UUID) -> Binding<SpecSection> {
        Binding(
            get: { [weak self] in
                self?.spec.sections.first { $0.id == id }
                    ?? SpecSection(title: "", kind: .text(source: .body("")))
            },
            set: { [weak self] newValue in
                guard let self,
                      let i = self.spec.sections.firstIndex(where: { $0.id == id })
                else { return }
                self.spec.sections[i] = newValue
                self.scheduleSave()
            })
    }

    // MARK: - Config (dossier.toml) mutations

    func saveConfig(_ newConfig: ProjectConfig) {
        config = newConfig
        if let configURL { try? SpecIO.writeConfig(config, to: configURL) }
        render()
    }

    // MARK: - Persistence + render

    /// Debounced (~300 ms): write the spec to disk, then re-render. The write is
    /// the same one that persists the user's edits — there is no separate save
    /// (DESKTOP_APP_SPEC §8).
    func scheduleSave() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistSpec()
            self.render()
        }
    }

    func persistSpec() {
        guard let url = specURL(for: currentSpec) else { return }
        try? SpecIO.writeSpec(spec, to: url)
    }

    /// Run the engine off the main thread; publish back on the main actor (§8).
    func render() {
        guard let engine, let projectURL else {
            lastResult = nil
            return
        }
        let name = currentSpec.name
        isRendering = true
        // Supersede any render still in flight so overlapping edits don't pile
        // up blocked subprocesses.
        runningProcess?.terminate()
        Task.detached(priority: .userInitiated) {
            let outcome = engine.forge(specName: name, root: projectURL) { process in
                Task { @MainActor in self.runningProcess = process }
            }
            await MainActor.run {
                self.runningProcess = nil
                self.apply(outcome)
            }
        }
    }

    private var runningProcess: Process?

    private func apply(_ outcome: EngineOutcome) {
        withAnimation(Theme.Motion.gentle) {
            isRendering = false
            switch outcome {
            case let .forged(result):
                lastResult = result
                engineError = nil
            case let .engineFailure(message):
                engineError = message
            }
        }
    }

    // MARK: - Derived render state

    /// The materialized prompt Copy/Save emit — only when the last render succeeded.
    var materializedPrompt: String? {
        guard let result = lastResult, result.ok else { return nil }
        return result.prompt
    }

    var canOutput: Bool { materializedPrompt?.isEmpty == false }

    func flashStatus(_ message: String) {
        withAnimation(Theme.Motion.bouncy) { transientStatus = message }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if self?.transientStatus == message {
                withAnimation(Theme.Motion.gentle) { self?.transientStatus = nil }
            }
        }
    }
}
