import SwiftUI

// Middle pane — the prompt builder (DESKTOP_APP_SPEC §6, DESIGN.md §builder-pane).
// The ordered list of the spec's sections as editable cards in render order.
struct BuilderView: View {
    @Environment(AppModel.self) private var model
    @Binding var showPromptLibrary: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            content
        }
        .background(Theme.Colors.surface)
        // Drag-and-drop from the explorer: each dropped relative path becomes a
        // `file` section (multi-file supported).
        .dropDestination(for: String.self) { paths, _ in
            for path in paths { model.addFileSection(relativePath: path) }
            return !paths.isEmpty
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

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                showPromptLibrary = true
            } label: { Label("Prompts", systemImage: "books.vertical") }
                .buttonStyle(TertiaryButtonStyle())
                .fixedSize()
        }
        .padding(Theme.Spacing.md)
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
            List {
                ForEach(model.spec.sections) { section in
                    VStack(spacing: Theme.Spacing.xs) {
                        SectionCardView(sectionID: section.id)
                        // A clear delimiter + accent "+" to insert after this card.
                        InsertDelimiter(afterID: section.id)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs, leading: Theme.Spacing.md,
                        bottom: Theme.Spacing.xs, trailing: Theme.Spacing.md))
                }
                .onMove { offsets, destination in
                    model.moveSections(from: offsets, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

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
