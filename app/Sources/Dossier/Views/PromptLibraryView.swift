import SwiftUI

// The prompt library + tree-filter editor (DESKTOP_APP_SPEC §6, §11): edits the
// [prompts] table and [tree] include/exclude lists in dossier.toml. A text
// section can reference a saved prompt by name instead of an inline body.
struct PromptLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // Local working copies; committed to disk on Save.
    @State private var prompts: [PromptEntry] = []
    @State private var treeExclude: String = ""
    @State private var treeInclude: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    promptsSection
                    treeSection
                }
                .padding(Theme.Spacing.lg)
            }
            Divider().overlay(Theme.Colors.hairline)
            footer
        }
        .frame(width: 560, height: 520)
        .background(Theme.Colors.surface)
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Prompt Library")
                .font(Theme.Typography.headingLg)
                .foregroundStyle(Theme.Colors.ink)
            Spacer()
            Text("dossier.toml")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        }
        .padding(Theme.Spacing.lg)
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Reusable prompts", "Reference one from a text section.")
            ForEach($prompts) { $entry in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        TextField("name", text: $entry.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        Spacer()
                        Button {
                            prompts.removeAll { $0.id == entry.id }
                        } label: { Image(systemName: "trash").imageScale(.small) }
                            .buttonStyle(IconButtonStyle())
                    }
                    TextEditor(text: $entry.text)
                        .font(Theme.Typography.bodyMd)
                        .foregroundStyle(Theme.Colors.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 64)
                        .padding(Theme.Spacing.xs)
                        .surfaceTile(fill: Theme.Colors.surfaceElevated)
                }
                .padding(Theme.Spacing.sm)
                .surfaceTile(fill: Theme.Colors.surface)
            }
            Button {
                prompts.append(PromptEntry(name: "", text: ""))
            } label: { Label("Add Prompt", systemImage: "plus") }
                .buttonStyle(TertiaryButtonStyle())
        }
    }

    private var treeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Tree filters",
                         "Comma-separated globs applied to every tree section.")
            SettingsRow(label: "Exclude") {
                TextField("docs, *.snap", text: $treeExclude)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
            }
            SettingsRow(label: "Include") {
                TextField("dist", text: $treeInclude)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
            }
        }
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typography.headingSm).foregroundStyle(Theme.Colors.ink)
            Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.mute)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Save") { save(); dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Load / save

    private func load() {
        prompts = model.config.prompts
            .sorted { $0.key < $1.key }
            .map { PromptEntry(name: $0.key, text: $0.value) }
        treeExclude = model.config.treeExclude.joined(separator: ", ")
        treeInclude = model.config.treeInclude.joined(separator: ", ")
    }

    private func save() {
        var dict: [String: String] = [:]
        for entry in prompts where !entry.name.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[entry.name] = entry.text
        }
        var newConfig = model.config
        newConfig.prompts = dict
        newConfig.treeExclude = splitList(treeExclude)
        newConfig.treeInclude = splitList(treeInclude)
        model.saveConfig(newConfig)
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct PromptEntry: Identifiable {
    let id = UUID()
    var name: String
    var text: String
}
