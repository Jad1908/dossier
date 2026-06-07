import SwiftUI

// One spec section, editable inline (DESIGN.md §section-card). Header carries
// the type badge, an editable title, a reorder handle, and remove. The body
// changes by section kind.
struct SectionCardView: View {
    @Environment(AppModel.self) private var model
    let sectionID: UUID

    private var binding: Binding<SpecSection> { model.binding(for: sectionID) }
    private var isSelected: Bool { model.selectedSectionID == sectionID }

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
        .contentShape(Rectangle())
        .onTapGesture { model.selectedSectionID = sectionID }
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
                            let first = model.config.promptNames.first ?? ""
                            binding.kind = .text(source: .prompt(first))
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
            set: { binding.kind = .text(source: .prompt($0)) })
    }
}

// MARK: - File section body

private struct FileSectionBody: View {
    let section: SpecSection

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "doc.text").imageScale(.small)
                .foregroundStyle(Theme.Colors.mute)
            Text(section.filePath ?? "")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.mute)
                .textSelection(.enabled)
            Spacer()
        }
        .help("Path is set from the explorer; remove this card to un-include the file.")
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
