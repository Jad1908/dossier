import SwiftUI

// One spec section, editable inline (DESIGN.md §section-card). Header carries
// the type badge, an editable title, a reorder handle, and remove. The body
// changes by section kind.
struct SectionCardView: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    private var binding: Binding<SpecSection> { model.binding(for: sectionID) }
    private var isSelected: Bool { model.selectedSectionID == sectionID }
    @State private var hovering = false

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
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.selectedSectionID = isSelected ? nil : sectionID }
        .animation(Theme.Motion.smooth, value: isSelected)
        .animation(Theme.Motion.snappy, value: hovering)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .scale(scale: 0.92).combined(with: .opacity)))
    }

    // MARK: - Header

    private func header(_ section: SpecSection) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Theme.Colors.stone)
                .help("Drag to reorder")
            TypeBadge(kind: section.kind)
            TextField("Title", text: binding.title)
                .textFieldStyle(.plain)
                .font(Theme.Typography.headingSm)
                .foregroundStyle(Theme.Colors.ink)
                .onSubmit { model.selectedSectionID = sectionID }
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

    // MARK: - Body by kind

    @ViewBuilder
    private func body(_ section: SpecSection) -> some View {
        switch section.kind {
        case .text:    TextSectionBody(binding: binding)
        case .file:    FileSectionBody(section: section)
        case .tree:    TreeSectionBody(binding: binding)
        }
    }
}

// MARK: - Text section body

private struct TextSectionBody: View {
    @Environment(AppModel.self) private var model
    @Binding var binding: SpecSection

    private var isInline: Bool {
        if case .text(.body) = binding.kind { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SegmentedControl(
                selection: Binding(
                    get: { isInline },
                    set: { inline in
                        if inline {
                            binding.kind = .text(source: .body(currentBody))
                        } else {
                            usePrompt(model.config.promptNames.first ?? "")
                        }
                    }),
                options: [(true, "Inline body"), (false, "Saved prompt")])

            if isInline {
                TextEditor(text: bodyBinding)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(Theme.Spacing.xs)
                    .surfaceTile(fill: Theme.Colors.surfaceElevated)
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
            Text("Tree include/exclude patterns live in dossier.toml — edit them in the Prompts library.")
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
    @State private var showFilePicker = false

    private var index: Int { model.insertionIndex(after: afterID) }

    var body: some View {
        // The whole row — both rules and the pill — is the menu trigger, so a
        // click anywhere along the accent line inserts a section here.
        Menu {
            Button { model.addTextSection(at: index) } label: {
                Label("Text", systemImage: "text.alignleft")
            }
            Button { model.addTreeSection(at: index) } label: {
                Label("Tree", systemImage: "list.bullet.indent")
            }
            Button { showFilePicker = true } label: {
                Label("File…", systemImage: "doc")
            }
        } label: {
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .opacity(hovering ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help("Add a section here")
        .popover(isPresented: $showFilePicker, arrowEdge: .bottom) {
            FilePickerPopover { rel in
                model.addFileSection(relativePath: rel, at: index)
                showFilePicker = false
            }
            .environment(model)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(hovering ? Theme.Colors.accentText.opacity(0.35) : Theme.Colors.hairline)
            .frame(height: 1)
    }
}
