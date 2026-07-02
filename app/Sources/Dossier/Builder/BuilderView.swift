import SwiftUI
import AppKit

// Middle pane — the prompt builder (DESKTOP_APP_SPEC §6, DESIGN.md §builder-pane).
// The ordered list of the spec's sections as editable cards in render order.
struct BuilderView: View {
    @Environment(AppModel.self) private var model
    @Binding var showPromptLibrary: Bool
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(model.spec.sections) { section in
                            SectionCardView(sectionID: section.id)
                                .id(section.id)   // scroll anchor for keyboard navigation
                            // A clear delimiter + accent "+" to insert after this card.
                            InsertDelimiter(afterID: section.id)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.md)
                }
                // Keyboard navigation and moves keep the active card on screen.
                // The nil anchor scrolls the minimum needed, so nothing shifts
                // while the card is already fully visible; mouse selection never
                // issues a request, so clicks can't yank the scroll position.
                .onChange(of: model.scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(Theme.Motion.smooth) {
                        proxy.scrollTo(request.id, anchor: nil)
                    }
                }
                // All keyboard navigation lives in handleCommandKey (the AppKit
                // monitor): the list itself is deliberately NOT .focusable() — a
                // focusable ancestor makes SwiftUI silently refuse every
                // programmatic focus write to the text fields inside it (Enter
                // could never focus a card's editor while it was there).
                .onChange(of: model.selectedSectionIDs) { _, ids in
                    guard !ids.isEmpty, isEditingText else { return }
                    // The selection changed while a text field holds focus. If
                    // the focus is the newly selected card's own editor (the
                    // click that selected the card landed in its field) or the
                    // explorer's filter (files added while typing a search),
                    // leave it alone. Otherwise the user clicked a *different*
                    // card while an old field — or a stray AppKit focus grant —
                    // still held the keys: step out so the keyboard follows the
                    // selection. Deferred a tick so the field's own focus
                    // onChange has settled first.
                    DispatchQueue.main.async {
                        guard isEditingText, !model.explorerFilterFocused else { return }
                        if let editing = model.editingSectionID, ids == [editing] { return }
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
                // Ctrl+Arrow while editing a field: jump between sections
                // mid-edit. This onKeyPress fires because the focused field is
                // a descendant; outside an edit the monitor consumes the key
                // before it gets here.
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard press.modifiers.contains(.control) else { return .ignored }
                    model.moveSelectionCursor(up: press.key == .upArrow)
                    return .handled
                }
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
    /// - `↑` / `↓` (plain, ⇧, ⌘), Return, and ⌫/⌦ run the section navigation
    ///   here so a selected card is never keyboard-dead — the list's onKeyPress
    ///   handlers only fire when it truly holds focus, which requires the
    ///   system keyboard-navigation setting. They remain as a fallback.
    private func handleCommandKey(_ event: NSEvent) -> Bool {
        guard model.currentSpecExists else { return false }
        if isEditingText {
            // A section's title/body is genuinely being edited: Esc steps out
            // and selects the card (handled here rather than onKeyPress, whose
            // focus scope AppKit-level focus can bypass); every other key
            // belongs to the field.
            if let editing = model.editingSectionID {
                guard event.keyCode == 53 else { return false }   // Esc
                NSApp.keyWindow?.makeFirstResponder(nil)   // resign the field editor
                model.selectOnly(editing)
                return true
            }
            // The explorer's filter is the one main-window field that doesn't
            // register as editing — typing there is intentional, stand down.
            if model.explorerFilterFocused { return false }
            // Ghost focus: AppKit handed the field editor out on its own
            // (typically to the first card's title when the window comes up or
            // a sheet closes) — no SwiftUI state accounts for it and the user
            // never asked for it. This is the state that killed the command
            // keys and let a shortcut keystroke land in the first section's
            // title. Reclaim the keyboard and run the key as a command.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }

        // Arrow keys carry .function/.numericPad on their own — strip them so
        // a plain ↑ still reads as "no modifiers held".
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])

        // Navigation keys, owned here rather than by the list's onKeyPress:
        // the .focusable() list only receives real focus while the system's
        // keyboard-navigation setting is on, so on a default macOS setup the
        // SwiftUI handlers never fire and cards went keyboard-dead. The
        // monitor doesn't depend on focus at all. (When the list does hold
        // focus, consuming the event here just means onKeyPress never sees
        // it — same outcome, no double handling.)
        switch event.keyCode {
        case 126, 125:                       // ↑ / ↓
            return handleArrow(up: event.keyCode == 126, mods: mods)
        case 36 where mods.isEmpty:          // Return → edit the selected card
            guard model.selectedSectionIDs.count == 1,
                  let id = model.selectedSectionIDs.first else { return false }
            model.requestEdit(id)            // the claiming field takes focus itself
            return true
        case 51 where mods.isEmpty,          // ⌫
             117 where mods.isEmpty:         // ⌦ — delete the selection
            guard !model.selectedSectionIDs.isEmpty else { return false }
            model.deleteSelection()
            return true
        case 53 where mods.isEmpty:          // ⎋ — drop the selection
            // Never while a popover is up: Esc must reach it to close it, and
            // AppKit doesn't demote the main window's key status for popovers.
            guard !model.selectedSectionIDs.isEmpty, !popoverIsOpen else { return false }
            model.clearSelection()
            return true
        default:
            break
        }

        // Only bare keys, optionally with Shift (which picks the structural
        // variant of an add key). ⌘/⌃/⌥ combos belong to the menu, so leave
        // them alone.
        guard mods.subtracting(.shift).isEmpty else { return false }
        let shift = mods.contains(.shift)

        if event.characters == "?" { showShortcuts = true; return true }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t": shift ? model.addTreeSection() : model.addTextSection(); return true
        case "f": shift ? requestFolderPicker() : requestFilePicker(); return true
        default:  return false
        }
    }

    /// ↑/↓ section navigation at the monitor layer, so it works from any focus
    /// state. Mirrors the list's onKeyPress arrows: plain = move the cursor,
    /// ⇧ = grow the range, ⌘ = move the selected cards, ⌃ = plain move (the
    /// mid-edit ⌃ jump stays with onKeyPress, which sees the key because the
    /// focused field sits inside the list's focus scope). Skipped when a table
    /// view owns the responder, so it never steals another list's navigation.
    private func handleArrow(up: Bool, mods: NSEvent.ModifierFlags) -> Bool {
        guard !model.spec.sections.isEmpty,
              !(NSApp.keyWindow?.firstResponder is NSTableView) else { return false }
        if mods.isEmpty || mods == .control {
            model.moveSelectionCursor(up: up)
        } else if mods == .shift {
            model.stepExtendSelection(up: up)
        } else if mods == .command {
            guard !model.selectedSectionIDs.isEmpty else { return false }
            up ? model.moveSelectionUp() : model.moveSelectionDown()
        } else {
            return false
        }
        return true
    }

    /// True while any popover (insert choices, file/folder picker) is up.
    private var popoverIsOpen: Bool {
        NSApp.windows.contains {
            $0.isVisible && String(describing: type(of: $0)).contains("PopoverWindow")
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
                // Only keys addressed to this builder's own window, and only
                // while it's key — never a background window, the Settings
                // panel, or a popover (popovers get key events of their own
                // while the main window still reports isKeyWindow, so the
                // event's window is the only reliable discriminator).
                guard let self, let window = self.view?.window, window.isKeyWindow,
                      event.window === window,
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
