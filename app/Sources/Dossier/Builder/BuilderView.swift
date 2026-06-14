import SwiftUI
import AppKit

// Middle pane — the prompt builder (DESKTOP_APP_SPEC §6, DESIGN.md §builder-pane).
// The ordered list of the spec's sections as editable cards in render order.
struct BuilderView: View {
    @Environment(AppModel.self) private var model
    @Binding var showPromptLibrary: Bool
    @FocusState private var listFocused: Bool
    @State private var showFolderPicker = false

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
