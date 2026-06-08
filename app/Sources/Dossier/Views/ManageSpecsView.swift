import SwiftUI

// Manage Specs — add and delete the project's context.*.toml files in one place
// (the quick "New Spec…" action stays in the toolbar switcher). Consistent with
// the Prompt Library sheet: a header, a scrollable list of spec cards, and a
// create row pinned at the bottom.
struct ManageSpecsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var pendingDelete: SpecRef?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            list
            Divider().overlay(Theme.Colors.hairline)
            createRow
        }
        .frame(width: 520, height: 480)
        .background(Theme.Colors.surface)
        .confirmationDialog(
            "Delete \(pendingDelete?.fileName ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { ref in
            Button("Delete", role: .destructive) {
                withAnimation(Theme.Motion.smooth) { model.deleteSpec(ref) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { ref in
            Text("This permanently removes \(ref.fileName) from the project folder. "
                 + "This can’t be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manage Specs")
                    .font(Theme.Typography.headingLg)
                    .foregroundStyle(Theme.Colors.ink)
                if let folder = model.projectURL?.lastPathComponent {
                    Text(folder)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if model.availableSpecs.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.Colors.mute)
                Text("No specs in this folder yet")
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Text("Create one below to start building a prompt.")
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.mute)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.availableSpecs) { ref in
                        SpecRowView(ref: ref) { pendingDelete = ref }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .scale(scale: 0.94).combined(with: .opacity)))
                    }
                }
                .padding(Theme.Spacing.lg)
                .animation(Theme.Motion.smooth, value: model.availableSpecs)
            }
        }
    }

    // MARK: - Create row

    private var createRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("New spec name (blank = default context.toml)", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Button("Create", action: create)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(nameTaken)
        }
        .padding(Theme.Spacing.lg)
    }

    private var trimmedName: String? {
        let t = newName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// The target file for the name being typed already exists.
    private var nameTaken: Bool {
        model.availableSpecs.contains { $0.name == trimmedName }
    }

    private func create() {
        guard !nameTaken else { return }
        withAnimation(Theme.Motion.bouncy) { model.createSpec(named: trimmedName) }
        newName = ""
    }
}

// MARK: - One spec row

private struct SpecRowView: View {
    @Environment(AppModel.self) private var model
    let ref: SpecRef
    let onDelete: () -> Void
    @State private var hovering = false

    private var isCurrent: Bool { ref == model.currentSpec }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text")
                .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.mute)

            VStack(alignment: .leading, spacing: 1) {
                Text(ref.displayName)
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.ink)
                Text(ref.fileName)
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Colors.mute)
            }

            Spacer()

            if isCurrent {
                StatusBadge(tone: .success, text: "Current")
            }
            if let count = model.sectionCount(for: ref) {
                Text("\(count) section\(count == 1 ? "" : "s")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.mute)
            }
            Button(action: onDelete) {
                Image(systemName: "trash").imageScale(.small)
            }
            .buttonStyle(IconButtonStyle())
            .help("Delete \(ref.fileName)")
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            isCurrent ? Theme.Colors.accentSoft
                      : (hovering ? Theme.Colors.hairlineSoft : Color.clear),
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(isCurrent ? Theme.Colors.accentPrimary.opacity(0.5)
                                        : Theme.Colors.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !isCurrent { model.switchSpec(to: ref) } }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.smooth, value: isCurrent)
    }
}
