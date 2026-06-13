import SwiftUI
import AppKit

// One spec section, editable inline (DESIGN.md §section-card). Header carries
// the type badge, an editable title, a reorder handle, and remove. The body
// changes by section kind.
struct SectionCardView: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    private var binding: Binding<SpecSection> { model.binding(for: sectionID) }
    private var isSelected: Bool { model.isSelected(sectionID) }

    /// An inline text body owns the Enter-to-edit request (it focuses its
    /// editor); every other kind falls back to focusing the title for a rename.
    private var isInlineText: Bool {
        if case .text(.body) = binding.wrappedValue.kind { return true }
        return false
    }
    @State private var hovering = false
    @State private var titleHovering = false
    @State private var dropTargeted = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        let section = binding.wrappedValue
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header(section)
            body(section)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Colors.accentPrimary.opacity(0.6) : Theme.Colors.hairline,
                    lineWidth: 1)
        )
        .background(
            isSelected
                ? Theme.Colors.accentSoft.clipShape(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                : nil
        )
        // A whisper of lift on selection / hover — organic, not springy chrome.
        .scaleEffect(isSelected ? 1.01 : (hovering ? 1.004 : 1))
        // Drop target for the reorder drag (and for explorer files): a payload
        // dropped on a card lands just before it. The accent line on top shows
        // where the drop will go.
        .overlay(alignment: .top) {
            if dropTargeted {
                Capsule().fill(Theme.Colors.accentPrimary)
                    .frame(height: 2)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { payloads, _ in
            guard let myIndex = model.spec.sections.firstIndex(where: { $0.id == sectionID })
            else { return false }
            var handled = false
            for payload in payloads {
                if let dragged = SectionDrag.id(from: payload) {
                    if dragged != sectionID {
                        model.dropReorder(draggedID: dragged, to: myIndex)
                        handled = true
                    }
                } else {
                    model.addFileSection(relativePath: payload, at: myIndex)
                    handled = true
                }
            }
            return handled
        } isTargeted: { dropTargeted = $0 }
        .onHover { hovering = $0 }
        // Shift = extend a range, Cmd = toggle one card, plain = select only
        // this one. Read the live modifier flags so one gesture covers all three.
        .onTapGesture {
            let mods = NSEvent.modifierFlags
            if mods.contains(.shift) {
                model.extendSelection(to: sectionID)
            } else if mods.contains(.command) {
                model.toggleSectionSelection(sectionID)
            } else {
                model.selectSection(sectionID)
            }
        }
        .animation(Theme.Motion.smooth, value: isSelected)
        .animation(Theme.Motion.snappy, value: hovering)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .scale(scale: 0.92).combined(with: .opacity)))
    }

    /// The floating drag image: the dragged card's title, or a count when it's
    /// part of a multi-selection being moved together.
    @ViewBuilder
    private func dragPreview(_ section: SpecSection) -> some View {
        if isSelected, model.selectedSectionIDs.count > 1 {
            Label("\(model.selectedSectionIDs.count) sections",
                  systemImage: "square.stack.3d.up")
                .padding(Theme.Spacing.xs)
        } else {
            Label(section.title.isEmpty ? section.kind.label : section.title,
                  systemImage: section.kind.symbolName)
                .padding(Theme.Spacing.xs)
        }
    }

    // MARK: - Header

    private func header(_ section: SpecSection) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Theme.Colors.stone)
                .padding(Theme.Spacing.xs)   // a forgiving grab area
                .contentShape(Rectangle())
                .draggable(SectionDrag.payload(for: sectionID)) {
                    dragPreview(section)
                }
                .help(isSelected && model.selectedSectionIDs.count > 1
                      ? "Drag to move the \(model.selectedSectionIDs.count) selected sections"
                      : "Drag to reorder")
            TypeBadge(kind: section.kind)
            titleField
            Spacer()
            Button {
                model.removeSection(id: sectionID)
            } label: {
                Image(systemName: "trash").imageScale(.small)
            }
            .buttonStyle(IconButtonStyle())
            .help("Remove section")
        }
    }

    /// The section title, styled to read as an editable field: a quiet pill that
    /// brightens on hover (with a pencil hint) and shows an accent ring while
    /// focused. Its own tap focuses the field directly so the first click lands —
    /// the card's whole-surface selection gesture no longer eats it.
    private var titleField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            TextField("Title", text: binding.title)
                .textFieldStyle(.plain)
                .font(Theme.Typography.headingSm)
                .foregroundStyle(Theme.Colors.ink)
                .focused($titleFocused)
                .onSubmit { titleFocused = false }
                .onChange(of: titleFocused) { _, focused in
                    if focused { model.beginEditing(sectionID) }
                    else { model.endEditing(sectionID) }
                }
                .onChange(of: model.editRequestID) { _, id in
                    // Only claim the request for kinds with no text body.
                    guard id == sectionID, !isInlineText else { return }
                    titleFocused = true
                    model.consumeEditRequest(sectionID)
                }
            Image(systemName: "pencil")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.mute)
                .opacity(titleHovering && !titleFocused ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(titleFocused ? Theme.Colors.surface
                      : (titleHovering ? Theme.Colors.surfaceElevated : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(
                    titleFocused ? Theme.Colors.accentPrimary.opacity(0.5)
                        : (titleHovering ? Theme.Colors.hairline : .clear),
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { titleHovering = $0 }
        .onTapGesture { titleFocused = true }
        .animation(Theme.Motion.snappy, value: titleHovering)
        .animation(Theme.Motion.snappy, value: titleFocused)
        .help("Click to rename this section")
    }

    // MARK: - Body by kind

    @ViewBuilder
    private func body(_ section: SpecSection) -> some View {
        switch section.kind {
        case .text:    TextSectionBody(binding: binding)
        case .file:    FileSectionBody(section: section)
        case .tree:    TreeSectionBody(binding: binding)
        case .csv:     CsvSectionBody(binding: binding)
        }
    }
}

// MARK: - Text section body

private struct TextSectionBody: View {
    @Environment(AppModel.self) private var model
    @Binding var binding: SpecSection
    @FocusState private var editing: Bool

    private var isInline: Bool {
        if case .text(.body) = binding.kind { return true }
        return false
    }

    private var hasPrompts: Bool { !model.config.promptNames.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SegmentedControl(
                selection: Binding(
                    get: { isInline },
                    set: { inline in
                        if inline {
                            binding.kind = .text(source: .body(currentBody))
                        } else if hasPrompts {
                            usePrompt(model.config.promptNames.first ?? "")
                        }
                        // With no saved prompts, "Saved prompt" is disabled and
                        // this setter never reaches the prompt branch — so the
                        // section can't be pointed at an empty/unknown prompt,
                        // which the engine would (rightly) flag as an error.
                    }),
                options: [(true, "Inline body"), (false, "Saved prompt")],
                // false == the "Saved prompt" segment.
                disabledValues: hasPrompts ? [] : [false],
                disabledHelp: "Add a prompt in the Prompts library to reuse it here.")

            if isInline {
                TextEditor(text: bodyBinding)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(Theme.Spacing.xs)
                    .surfaceTile(fill: Theme.Colors.surfaceElevated)
                    .focused($editing)
                    .onChange(of: editing) { _, focused in
                        if focused { model.beginEditing(binding.id) }
                        else { model.endEditing(binding.id) }
                    }
                    .onChange(of: model.editRequestID) { _, id in
                        guard id == binding.id else { return }
                        editing = true
                        model.consumeEditRequest(binding.id)
                    }
            } else {
                savedPromptPicker
            }
        }
    }

    private var savedPromptPicker: some View {
        let names = model.config.promptNames
        return Group {
            if names.isEmpty {
                Text("No saved prompts yet — add one in the Prompts library.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.mute)
            } else {
                Picker("Prompt", selection: promptBinding) {
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var currentBody: String {
        if case let .text(.body(b)) = binding.kind { return b }
        return ""
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { currentBody },
            set: { binding.kind = .text(source: .body($0)) })
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: {
                if case let .text(.prompt(n)) = binding.kind { return n }
                return ""
            },
            set: { usePrompt($0) })
    }

    /// Point the section at a saved prompt, defaulting the title to the prompt
    /// name when the title is still the generic placeholder (change 3).
    private func usePrompt(_ name: String) {
        var updated = binding
        if updated.title.isEmpty || updated.title == "NEW SECTION" {
            updated.title = name
        }
        updated.kind = .text(source: .prompt(name))
        binding = updated
    }
}

// MARK: - File section body

private struct FileSectionBody: View {
    @Environment(AppModel.self) private var model
    let section: SpecSection
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "doc.text").imageScale(.small)
                .foregroundStyle(Theme.Colors.mute)
            Text(section.filePath ?? "")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.mute)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            Button {
                if let path = section.filePath { model.previewFile(relativePath: path) }
            } label: {
                Image(systemName: "magnifyingglass").imageScale(.small)
            }
            .buttonStyle(IconButtonStyle())
            .help("Preview this file")
            Button {
                showPicker = true
            } label: {
                Label("Change…", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.Typography.caption)
            }
            .buttonStyle(IconButtonStyle())
            .help("Choose a different file for this section")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                FilePickerPopover { rel in
                    model.setFileSection(section.id, relativePath: rel)
                    showPicker = false
                }
                .environment(model)
            }
        }
    }
}

// MARK: - Tree section body

private struct TreeSectionBody: View {
    @Binding var binding: SpecSection

    private var maxDepth: Int {
        if case let .tree(d, _) = binding.kind { return d }
        return -1
    }
    private var useGitignore: Bool {
        if case let .tree(_, g) = binding.kind { return g }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Stepper(value: depthBinding, in: -1...50) {
                    Text(depthLabel)
                        .font(Theme.Typography.bodyMd)
                        .foregroundStyle(Theme.Colors.body)
                }
            }
            Toggle(isOn: gitignoreBinding) {
                Text("Respect .gitignore")
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.body)
            }
            .toggleStyle(.switch)
            .tint(Theme.Colors.accentPrimary)
            Text("Tree include/exclude patterns live in .dossier/config.toml — edit them in the Prompts library.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        }
    }

    private var depthLabel: String {
        switch maxDepth {
        case -1: return "Depth: unlimited"
        case 0:  return "Depth: root only"
        default: return "Depth: \(maxDepth) level\(maxDepth == 1 ? "" : "s")"
        }
    }

    private var depthBinding: Binding<Int> {
        Binding(
            get: { maxDepth },
            set: { binding.kind = .tree(maxDepth: $0, useGitignore: useGitignore) })
    }
    private var gitignoreBinding: Binding<Bool> {
        Binding(
            get: { useGitignore },
            set: { binding.kind = .tree(maxDepth: maxDepth, useGitignore: $0) })
    }
}

// MARK: - Insert delimiter (change 2)

/// A stable delimiter between section cards — a hairline with a centered accent
/// "+" — that inserts a section (Text / Tree / File…) right after `afterID`.
/// Quiet by default, brighter on hover; opacity-only, so nothing jumps.
struct InsertDelimiter: View {
    @Environment(AppModel.self) private var model
    let afterID: UUID
    @State private var hovering = false
    @State private var dropTargeted = false
    @State private var showChoices = false
    @State private var showFilePicker = false

    private var index: Int { model.insertionIndex(after: afterID) }

    var body: some View {
        // A plain button (no menu chrome) over the whole row, so a click
        // anywhere along the line inserts a section; the line itself turns
        // accent on hover.
        Button { showChoices = true } label: {
            HStack(spacing: Theme.Spacing.sm) {
                rule
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("Add").font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Colors.accentText)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .background(Theme.Colors.accentSoft, in: Capsule())
                rule
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering || dropTargeted ? 1 : 0.4)
        .onHover { hovering = $0 }
        // Drop target: a reorder drag or an explorer file dropped on the
        // delimiter lands exactly here (after the card above).
        .dropDestination(for: String.self) { payloads, _ in
            for payload in payloads {
                if let dragged = SectionDrag.id(from: payload) {
                    model.dropReorder(draggedID: dragged, to: index)
                } else {
                    model.addFileSection(relativePath: payload, at: index)
                }
            }
            return !payloads.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.15), value: dropTargeted)
        .help("Add a section here")
        .popover(isPresented: $showChoices, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                choice("Text", "text.alignleft") { model.addTextSection(at: index) }
                choice("Tree", "list.bullet.indent") { model.addTreeSection(at: index) }
                choice("File…", "doc") {
                    // Hand off to the file picker on the next tick so the two
                    // popovers don't fight.
                    DispatchQueue.main.async { showFilePicker = true }
                }
            }
            .padding(Theme.Spacing.xs)
            .frame(width: 160)
        }
        .popover(isPresented: $showFilePicker, arrowEdge: .bottom) {
            FilePickerPopover { rel in
                model.addFileSection(relativePath: rel, at: index)
                showFilePicker = false
            }
            .environment(model)
        }
    }

    /// One row in the insert-choices popover.
    private func choice(_ label: String, _ symbol: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            showChoices = false
            action()
        } label: {
            Label(label, systemImage: symbol)
                .font(Theme.Typography.bodyMd)
                .foregroundStyle(Theme.Colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rule: some View {
        Rectangle()
            .fill(hovering ? Theme.Colors.accentText.opacity(0.35) : Theme.Colors.hairline)
            .frame(height: 1)
    }
}
