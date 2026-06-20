import SwiftUI
import AppKit

// Middle pane — the prompt builder (DESKTOP_APP_SPEC §6, DESIGN.md §builder-pane).
// The ordered list of the spec's sections as editable cards in render order.
struct BuilderView: View {
    @Environment(AppModel.self) private var model
    @Binding var showPromptLibrary: Bool
    @FocusState private var listFocused: Bool
    @State private var showFolderPicker = false
    @State private var showShortcuts = false
    // Fallbacks for the empty state, where there are no cards (and so no inline
    // "+ Add" delimiter) to anchor a keyboard-triggered picker on.
    @State private var showEmptyFilePicker = false
    @State private var showEmptyFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            if model.selectedSectionIDs.count > 1 {
                selectionBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
        }
        .animation(Theme.Motion.smooth, value: model.selectedSectionIDs)
        .background(Theme.Colors.surface)
        // Jupyter-style command keys are caught in AppKit, not via SwiftUI
        // focus: a key-window monitor runs them whenever the user isn't typing
        // in a text field, so they fire regardless of which view holds focus
        // (the .focusable() list was too fragile — keys leaked into title
        // fields). See `handleCommandKey`.
        .background(BuilderKeyMonitor(handle: handleCommandKey))
        // Cheat sheet for the keyboard shortcuts, opened with `?`.
        .sheet(isPresented: $showShortcuts) { ShortcutsCheatSheet() }
        // Pane-wide drop target (anywhere not claimed by a card/delimiter):
        // explorer file paths become `file` sections at the end; a section
        // payload (reorder drag that missed a specific target) moves to the end.
        .dropDestination(for: String.self) { payloads, _ in
            for payload in payloads {
                if let id = SectionDrag.id(from: payload) {
                    model.dropReorder(draggedID: id, to: model.spec.sections.count)
                } else {
                    model.addFileSection(relativePath: payload)
                }
            }
            return !payloads.isEmpty
        }
    }

    // A single row of action pills. Each label is fixed to one line; the pane's
    // minimum width (set in ContentView) guarantees the row always fits, so the
    // pills can never be squeezed into stacking.
    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                model.addTextSection()
            } label: { Label("Add Text", systemImage: "text.alignleft") }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()

            Button {
                model.addTreeSection()
            } label: { Label("Add Tree", systemImage: "list.bullet.indent") }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()

            Button {
                showFolderPicker = true
            } label: { Label("Add Folder", systemImage: "folder") }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()
                .popover(isPresented: $showFolderPicker, arrowEdge: .bottom) {
                    FolderPickerPopover { rel in
                        model.addFolderSection(relativePath: rel)
                        showFolderPicker = false
                    }
                    .environment(model)
                }

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                showPromptLibrary = true
            } label: { Label("Prompts", systemImage: "books.vertical") }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()
        }
        .padding(Theme.Spacing.md)
    }

    // Shown while one or more cards are selected: move the whole selection as a
    // block, delete it, or clear it. Reordering by hand stays available via drag.
    private var selectionBar: some View {
        let count = model.selectedSectionIDs.count
        return HStack(spacing: Theme.Spacing.sm) {
            Text("\(count) selected")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.accentText)

            Spacer(minLength: Theme.Spacing.sm)

            Button { model.moveSelectionUp() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(IconButtonStyle())
            .help("Move selection up")

            Button { model.moveSelectionDown() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(IconButtonStyle())
            .help("Move selection down")

            Button { model.deleteSelection() } label: {
                Label("Delete", systemImage: "trash")
                    .font(Theme.Typography.caption)
            }
            .buttonStyle(IconButtonStyle())
            .help("Delete \(count) sections")

            Button("Done") { model.clearSelection() }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.accentSoft)
    }

    @ViewBuilder
    private var content: some View {
        if !model.currentSpecExists {
            NoSpecView()
                .transition(.opacity)
        } else if model.spec.sections.isEmpty {
            emptyHint
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            // A plain ScrollView + VStack, deliberately not a List: List is an
            // NSTableView underneath, and with variable-height rows (growing
            // TextEditors) every insert/reorder/height change made it re-measure
            // rows, flash, and yank the scroll position back to the top. Pure
            // SwiftUI layout diffs in place and never touches the scroll offset.
            // Reordering is hand-rolled: the card's handle is draggable and
            // cards/delimiters are drop targets (see SectionDrag).
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.spec.sections) { section in
                        SectionCardView(sectionID: section.id)
                        // A clear delimiter + accent "+" to insert after this card.
                        InsertDelimiter(afterID: section.id)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, Theme.Spacing.md)
            }
            // Keyboard navigation. onKeyPress on this focusable list is greedy —
            // it fires even while a child TextEditor is being edited — so every
            // handler that would clash with typing first bails when a text field
            // holds the responder (isEditingText). Ctrl+Arrow is the exception:
            // it deliberately jumps between sections even mid-edit.
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onChange(of: model.selectedSectionIDs) { _, ids in
                if !ids.isEmpty, !isEditingText { listFocused = true }
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let up = press.key == .upArrow
                // Ctrl+Arrow: navigate between sections with priority over the
                // field, dropping out of any text edit in progress.
                if press.modifiers.contains(.control) {
                    listFocused = true            // resign the field editor
                    model.moveSelectionCursor(up: up)
                    return .handled
                }
                // Everything else must leave a field being edited untouched.
                guard !isEditingText else { return .ignored }
                if press.modifiers.contains(.command) {
                    up ? model.moveSelectionUp() : model.moveSelectionDown()
                } else if press.modifiers.contains(.shift) {
                    model.stepExtendSelection(up: up)
                } else {
                    model.moveSelectionCursor(up: up)
                }
                return .handled
            }
            .onKeyPress(.escape) {
                // Editing a section's title/body: step out and select that card.
                if let editing = model.editingSectionID {
                    listFocused = true          // resign the field editor
                    model.selectOnly(editing)
                    return .handled
                }
                // Any other field (CSV cell, etc.): let it handle its own Esc.
                if isEditingText { return .ignored }
                guard !model.selectedSectionIDs.isEmpty else { return .ignored }
                model.clearSelection()
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !isEditingText, !model.selectedSectionIDs.isEmpty else {
                    return .ignored
                }
                model.deleteSelection()
                return .handled
            }
            // Enter on a single selected card drops into editing its text box
            // (or its title, for sections without a text body).
            .onKeyPress(.return) {
                guard !isEditingText, model.selectedSectionIDs.count == 1,
                      let id = model.selectedSectionIDs.first else { return .ignored }
                model.requestEdit(id)
                return .handled
            }
        }
    }

    // MARK: - AppKit command keys

    /// Jupyter-style command keys, handled at the AppKit layer so they don't
    /// depend on the SwiftUI list holding focus. Returns true when the event is
    /// consumed. The whole scheme stands down while a text field is being edited
    /// (`isEditingText`) so the keys reach the field instead — that is the
    /// command-mode / edit-mode split.
    ///
    /// - `t` / `⇧t` add a text / tree section.
    /// - `f` / `⇧f` open the file / folder picker at the "+ Add" pill where the
    ///   new section will land (or a header-anchored fallback when empty).
    /// - `?` shows the cheat sheet.
    /// - `↑` / `↓` with nothing selected bootstrap a selection so navigation can
    ///   start; once something is selected the SwiftUI list owns the arrows
    ///   (including the ⌘/⇧/⌃ variants), so we leave those alone.
    private func handleCommandKey(_ event: NSEvent) -> Bool {
        guard model.currentSpecExists, !isEditingText else { return false }
        // Only bare keys, optionally with Shift (which picks the structural
        // variant of an add key). ⌘/⌃/⌥ combos belong to the menu and the
        // SwiftUI list handlers, so leave them alone.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.subtracting(.shift).isEmpty else { return false }
        let shift = mods.contains(.shift)

        if event.characters == "?" { showShortcuts = true; return true }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t": shift ? model.addTreeSection() : model.addTextSection(); return true
        case "f": shift ? requestFolderPicker() : requestFilePicker(); return true
        default:  return bootstrapArrow(event)
        }
    }

    /// First ↑/↓ when nothing is selected: land on a section so the SwiftUI list
    /// can take over. Skipped when the explorer's list owns the responder, so it
    /// never steals the explorer's own arrow navigation.
    private func bootstrapArrow(_ event: NSEvent) -> Bool {
        guard model.selectedSectionIDs.isEmpty, !model.spec.sections.isEmpty,
              !(NSApp.keyWindow?.firstResponder is NSTableView) else { return false }
        switch event.keyCode {
        case 126: model.moveSelectionCursor(up: true);  return true   // ↑ → last
        case 125: model.moveSelectionCursor(up: false); return true   // ↓ → first
        default:  return false
        }
    }

    /// Open the file picker. Normally it rides the inline "+ Add" delimiter at the
    /// insert point; with no sections there is no delimiter, so fall back to a
    /// popover on the empty-state hint.
    private func requestFilePicker() {
        if model.spec.sections.isEmpty { showEmptyFilePicker = true }
        else { model.requestInsertPicker(.file) }
    }

    private func requestFolderPicker() {
        if model.spec.sections.isEmpty { showEmptyFolderPicker = true }
        else { model.requestInsertPicker(.folder) }
    }

    /// True while a text field/editor holds the window's first responder — i.e.
    /// the user is typing. Backed by AppKit because the clashing keys are caught
    /// by this view's greedy onKeyPress before the field would see them.
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    // MARK: - Empty state

    private var emptyHint: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Colors.mute)
            Text("No sections yet")
                .font(Theme.Typography.headingSm)
                .foregroundStyle(Theme.Colors.ink)
            Text("Add a file from the explorer, or add a text or tree section above.")
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.mute)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // With no cards there is no "+ Add" delimiter to anchor on, so the f/⇧f
        // shortcuts open their pickers here instead.
        .overlay(alignment: .top) {
            Color.clear
                .frame(width: 1, height: 1)
                .popover(isPresented: $showEmptyFilePicker, arrowEdge: .bottom) {
                    FilePickerPopover { rel in
                        model.addFileSection(relativePath: rel)
                        showEmptyFilePicker = false
                    } onPickExternal: { abs in
                        model.addExternalFileSection(absolutePath: abs)
                        showEmptyFilePicker = false
                    }
                    .environment(model)
                }
                .popover(isPresented: $showEmptyFolderPicker, arrowEdge: .bottom) {
                    FolderPickerPopover { rel in
                        model.addFolderSection(relativePath: rel)
                        showEmptyFolderPicker = false
                    }
                    .environment(model)
                }
        }
    }
}

// MARK: - AppKit key monitor

/// Installs a key-window `keyDown` monitor for the builder's command keys. A
/// monitor (rather than SwiftUI `.onKeyPress`) means the keys fire from any
/// focus state, not only when a `.focusable()` view happens to hold focus.
/// `handle` returns true to swallow the event.
private struct BuilderKeyMonitor: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.handle = handle
        context.coordinator.install(view: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handle: ((NSEvent) -> Bool)?
        private weak var view: NSView?
        private var monitor: Any?

        func install(view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Only the key window's builder reacts — never a background
                // window or the Settings panel.
                guard let self, let window = self.view?.window, window.isKeyWindow,
                      let handle = self.handle else { return event }
                return handle(event) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: - Section reorder drag payload

/// Reorder drags share the String transfer type with explorer file drags (both
/// use `.draggable`/`.dropDestination(for: String.self)`), so a section drag is
/// marked with a URI prefix no relative file path can start with. Drop handlers
/// branch on it: a section id means "move me here", anything else is a file path.
enum SectionDrag {
    private static let prefix = "dossier-section://"

    static func payload(for id: UUID) -> String { prefix + id.uuidString }

    static func id(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}
