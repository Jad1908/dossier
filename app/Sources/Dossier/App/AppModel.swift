import SwiftUI
import AppKit
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

    /// Watches the open project for on-disk changes so the explorer stays in
    /// sync with files created outside the in-app actions. Not observed.
    @ObservationIgnored private var fileWatcher: FileSystemWatcher?
    var currentSpec = SpecRef(name: nil)

    // MARK: - Loaded documents

    var spec = Spec()
    var config = ProjectConfig()
    /// A spec/config load error (bad TOML) — distinct from a render error.
    private(set) var loadError: String?

    // MARK: - Builder selection

    /// The selected section cards. A set so several can be picked at once
    /// (Shift = range, Cmd = toggle) and moved or deleted as a group.
    private(set) var selectedSectionIDs: Set<UUID> = []

    /// The last card clicked without Shift — the fixed end of a Shift-range.
    private var selectionAnchor: UUID?

    /// The moving end of a Shift-range, so Shift+Arrow grows from where the last
    /// extension left off rather than from the anchor.
    private var selectionActiveEnd: UUID?

    func isSelected(_ id: UUID) -> Bool { selectedSectionIDs.contains(id) }

    /// The selected sections' current indices, ascending.
    private var selectedIndices: [Int] {
        spec.sections.enumerated()
            .filter { selectedSectionIDs.contains($0.element.id) }
            .map(\.offset)
    }

    // MARK: - Selection gestures

    /// Plain click: select only this card. Clicking the sole selection clears it.
    func selectSection(_ id: UUID) {
        if selectedSectionIDs == [id] {
            clearSelection()
        } else {
            selectedSectionIDs = [id]
            selectionAnchor = id
            selectionActiveEnd = id
        }
    }

    /// Cmd-click: add or remove this card from the selection.
    func toggleSectionSelection(_ id: UUID) {
        if selectedSectionIDs.contains(id) {
            selectedSectionIDs.remove(id)
        } else {
            selectedSectionIDs.insert(id)
        }
        selectionAnchor = id
        selectionActiveEnd = id
    }

    /// Shift-click: select the contiguous range from the anchor to this card.
    func extendSelection(to id: UUID) {
        guard let anchor = selectionAnchor,
              let a = spec.sections.firstIndex(where: { $0.id == anchor }),
              let b = spec.sections.firstIndex(where: { $0.id == id }) else {
            selectSection(id); return
        }
        let range = a <= b ? a...b : b...a
        selectedSectionIDs = Set(spec.sections[range].map(\.id))
        selectionActiveEnd = id
        // Anchor stays put so the range can be re-stretched from the same end.
    }

    func clearSelection() {
        selectedSectionIDs = []
        selectionAnchor = nil
        selectionActiveEnd = nil
    }

    // MARK: - Keyboard navigation

    /// ↑/↓: move the single selection to the previous/next card. With nothing
    /// selected, lands on the last/first card so the keyboard can take over.
    func moveSelectionCursor(up: Bool) {
        guard !spec.sections.isEmpty else { return }
        let next: Int
        if let cur = cursorIndex {
            next = up ? max(0, cur - 1) : min(spec.sections.count - 1, cur + 1)
        } else {
            next = up ? spec.sections.count - 1 : 0
        }
        selectSection(spec.sections[next].id)
    }

    /// Shift+↑/↓: grow or shrink the range by one card from its moving end,
    /// pivoting on the anchor.
    func stepExtendSelection(up: Bool) {
        guard !spec.sections.isEmpty else { return }
        guard selectionAnchor != nil, let end = selectionActiveEnd,
              let endIdx = spec.sections.firstIndex(where: { $0.id == end }) else {
            moveSelectionCursor(up: up); return
        }
        let nextIdx = up ? max(0, endIdx - 1) : min(spec.sections.count - 1, endIdx + 1)
        extendSelection(to: spec.sections[nextIdx].id)
    }

    /// The cursor for keyboard moves: the anchor if it's still around, else the
    /// nearest selected edge.
    private var cursorIndex: Int? {
        if let a = selectionAnchor,
           let i = spec.sections.firstIndex(where: { $0.id == a }) { return i }
        return selectedIndices.last
    }

    // MARK: - File preview

    /// The file shown in the floating preview panel — opened from the explorer's
    /// hover magnifier or a file section's magnifier. Nil = panel closed. One
    /// panel: a second preview repoints it rather than stacking windows.
    private(set) var filePreview: FilePreviewRequest?

    func previewFile(relativePath: String) {
        guard let projectURL else { return }
        withAnimation(Theme.Motion.smooth) {
            filePreview = FilePreviewRequest(
                relativePath: relativePath,
                url: projectURL.appendingPathComponent(relativePath),
                anchor: Self.currentClickAnchor())
        }
    }

    /// The mouse position at the moment the preview was requested, in the key
    /// window's content coordinates (top-left origin) — the same space as
    /// SwiftUI's `.global`. Nil when there's no window to resolve against,
    /// which the panel treats as "center it".
    private static func currentClickAnchor() -> CGPoint? {
        guard let window = NSApp.keyWindow, let content = window.contentView
        else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        var point = content.convert(inWindow, from: nil)
        if !content.isFlipped { point.y = content.bounds.height - point.y }
        return point
    }

    func closeFilePreview() {
        withAnimation(Theme.Motion.smooth) { filePreview = nil }
    }

    // MARK: - View zoom

    /// Whole-window UI scale (⌘+ / ⌘- / ⌘0). Applied at the window root so type,
    /// spacing, and icons scale together. Persisted and clamped to a sane range.
    var zoom: Double = Defaults.zoomLevel.clamped(to: Defaults.zoomRange) {
        didSet { Defaults.zoomLevel = zoom }
    }

    var canZoomIn: Bool { zoom < Defaults.zoomRange.upperBound - 1e-6 }
    var canZoomOut: Bool { zoom > Defaults.zoomRange.lowerBound + 1e-6 }

    func zoomIn()    { setZoom(zoom + Defaults.zoomStep) }
    func zoomOut()   { setZoom(zoom - Defaults.zoomStep) }
    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: Double) {
        // Round to the step grid so repeated presses don't drift on floating point.
        let stepped = (value / Defaults.zoomStep).rounded() * Defaults.zoomStep
        withAnimation(Theme.Motion.snappy) {
            zoom = stepped.clamped(to: Defaults.zoomRange)
        }
    }

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
        filePreview = nil   // a preview from another project would be stale
        Defaults.noteRecentProject(url)
        fileTreeRoot = FileNode(url: url, isDirectory: true, projectRoot: url)
        fileTreeRoot?.loadChildrenIfNeeded()
        watchProjectFiles(url)
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

    /// dossier's project files live in this folder under the project root,
    /// keeping the root clean. Mirrors the Python CLI's `DOSSIER_DIR`.
    static let dossierDirName = ".dossier"

    /// The `.dossier/` folder under the open project (specs + config live here).
    var dossierURL: URL? {
        projectURL?.appendingPathComponent(Self.dossierDirName)
    }

    func refreshSpecList() {
        guard let dossierURL else { availableSpecs = []; return }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: dossierURL.path)) ?? []
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
        dossierURL?.appendingPathComponent(ref.fileName)
    }

    var configURL: URL? {
        dossierURL?.appendingPathComponent("config.toml")
    }

    func switchSpec(to ref: SpecRef) {
        currentSpec = ref
        clearSelection()
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
        guard projectURL != nil else { return }
        let ref = SpecRef(name: name?.isEmpty == true ? nil : name)
        guard let url = specURL(for: ref) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? SpecIO.writeSpec(.starter, to: url)
        }
        refreshSpecList()
        reloadFileTree()
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
        reloadFileTree()
        loadSpecAndConfig()
        render()
    }

    // MARK: - File tree refresh

    /// Start (or restart) watching the project for files that appear outside the
    /// in-app actions, refreshing the explorer when they do.
    private func watchProjectFiles(_ url: URL) {
        fileWatcher = FileSystemWatcher(url: url) { [weak self] in
            MainActor.assumeIsolated { self?.reloadFileTree() }
        }
    }

    /// Refresh the tree from disk in place. `FileNode` is `@Observable`, so each
    /// reloaded directory whose contents changed re-renders its own row — files
    /// added inside an expanded subfolder surface, not just root-level ones.
    func reloadFileTree() {
        fileTreeRoot?.reloadLoadedChildren()
    }

    // MARK: - SpecSection mutations (all autosave + re-render)

    /// Where a new section lands by default: right after the selected card, or
    /// at the end when nothing is selected. Each add then selects the new
    /// section, so a run of adds stays in order below the selection.
    private var defaultInsertIndex: Int {
        if let last = selectedIndices.max() { return last + 1 }
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
            selectedSectionIDs = [section.id]
            selectionAnchor = section.id
        }
        scheduleSave()
    }

    func addFileSection(relativePath: String, at index: Int? = nil) {
        // Already in the prompt: select that card instead of adding a duplicate.
        if let existing = spec.sections.first(where: { $0.filePath == relativePath }) {
            selectedSectionIDs = [existing.id]
            selectionAnchor = existing.id
            return
        }
        let title = (relativePath as NSString).lastPathComponent.uppercased()
        insert(SpecSection(title: title,
                           kind: .forNewFile(relativePath: relativePath)),
               at: index)
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
        // Repointing follows the new file's kind. csv → csv keeps the row
        // scope but drops the column picks — they named the old file's header.
        switch (section.kind, SectionKind.forNewFile(relativePath: relativePath)) {
        case let (.csv(_, rows, _), .csv):
            section.kind = .csv(path: relativePath, rows: rows, columns: [])
        case let (_, newKind):
            section.kind = newKind
        }
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
            selectedSectionIDs.remove(id)
            if selectionAnchor == id { selectionAnchor = nil }
        }
        scheduleSave()
    }

    /// Delete every selected section at once.
    func deleteSelection() {
        guard !selectedSectionIDs.isEmpty else { return }
        withAnimation(Theme.Motion.smooth) {
            spec.sections.removeAll { selectedSectionIDs.contains($0.id) }
            clearSelection()
        }
        scheduleSave()
    }

    func moveSections(from offsets: IndexSet, to destination: Int) {
        withAnimation(Theme.Motion.smooth) {
            spec.sections.move(fromOffsets: offsets, toOffset: destination)
        }
        scheduleSave()
    }

    /// Move a group of sections (by id) to `offset` (pre-removal coordinates,
    /// like `onMove`'s destination), preserving their relative order. Used by
    /// the reorder drag when several cards are selected.
    func moveSections(ids: Set<UUID>, to offset: Int) {
        let offsets = IndexSet(spec.sections.enumerated()
            .filter { ids.contains($0.element.id) }.map(\.offset))
        guard !offsets.isEmpty else { return }
        moveSections(from: offsets, to: min(max(offset, 0), spec.sections.count))
    }

    /// Move one section to `offset` (pre-removal coordinates, like `onMove`'s
    /// destination) — the reorder drag's drop handler. No-op when the drop
    /// wouldn't change the order, so nothing saves or re-renders.
    func moveSection(id: UUID, to offset: Int) {
        guard let from = spec.sections.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(offset, 0), spec.sections.count)
        guard clamped != from, clamped != from + 1 else { return }
        moveSections(from: IndexSet(integer: from), to: clamped)
    }

    /// The reorder drag's drop: if the dragged card is part of a multi-selection,
    /// the whole selection lands at `offset`; otherwise just the dragged card.
    func dropReorder(draggedID: UUID, to offset: Int) {
        if selectedSectionIDs.contains(draggedID), selectedSectionIDs.count > 1 {
            moveSections(ids: selectedSectionIDs, to: offset)
        } else {
            moveSection(id: draggedID, to: offset)
        }
    }

    /// Block-move the selection one slot earlier / later, keeping it together.
    func moveSelectionUp() {
        guard let top = selectedIndices.min(), top > 0 else { return }
        moveSections(ids: selectedSectionIDs, to: top - 1)
    }

    func moveSelectionDown() {
        guard let bottom = selectedIndices.max(),
              bottom < spec.sections.count - 1 else { return }
        moveSections(ids: selectedSectionIDs, to: bottom + 2)
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

    // MARK: - Config (.dossier/config.toml) mutations

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

    private var renderIndicatorTask: Task<Void, Never>?

    /// Run the engine off the main thread; publish back on the main actor (§8).
    func render() {
        guard let engine, let projectURL else {
            lastResult = nil
            return
        }
        let name = currentSpec.name
        // Only surface the spinner if the render is slow enough to notice. Most
        // renders finish in well under this window, so typing a section no longer
        // makes the token-count indicator flicker on every keystroke.
        // 500 ms: typical renders finish in ~200-300 ms, so the spinner only
        // appears for genuinely slow renders instead of blipping in and out
        // at the threshold on every other edit.
        renderIndicatorTask?.cancel()
        renderIndicatorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isRendering = true
        }
        // Supersede any render still in flight so overlapping edits don't pile
        // up blocked subprocesses. The terminated render still returns (as an
        // engine failure — SIGTERM is a non-zero exit), so each render carries a
        // generation: only the latest may touch state. Without this, the stale
        // failure briefly swapped the preview to the error banner and back,
        // flashing the pane and resetting its scroll position on every edit
        // that landed mid-render.
        renderGeneration += 1
        let generation = renderGeneration
        runningProcess?.terminate()
        runningProcess = nil
        Task.detached(priority: .userInitiated) {
            let outcome = engine.forge(specName: name, root: projectURL) { process in
                Task { @MainActor in
                    if self.renderGeneration == generation {
                        self.runningProcess = process
                    } else {
                        // Already superseded before we got the handle.
                        process.terminate()
                    }
                }
            }
            await MainActor.run {
                guard self.renderGeneration == generation else { return }
                self.runningProcess = nil
                self.apply(outcome)
            }
        }
    }

    private var renderGeneration = 0
    private var runningProcess: Process?

    private func apply(_ outcome: EngineOutcome) {
        // Drop the result in place — no pane-wide animation. Animating every
        // render completion (one per keystroke, debounced) made the preview
        // reflow and jump its scroll position mid-edit. The preview drives its
        // own transitions (e.g. outline/full mode) where they're wanted.
        renderIndicatorTask?.cancel()
        // @Observable notifies on every write, equal value or not — guard the
        // no-op assignments so a routine render completion doesn't invalidate
        // every view that reads these.
        if isRendering { isRendering = false }
        switch outcome {
        case let .forged(result):
            lastResult = result
            if engineError != nil { engineError = nil }
        case let .engineFailure(message):
            engineError = message
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
