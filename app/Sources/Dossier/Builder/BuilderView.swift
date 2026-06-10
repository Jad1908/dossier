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
        // Pane-wide drop target (anywhere not claimed by a card/delimiter):
        // explorer file paths become `file` sections at the end; a section
        // payload (reorder drag that missed a specific target) moves to the end.
        .dropDestination(for: String.self) { payloads, _ in
            for payload in payloads {
                if let id = SectionDrag.id(from: payload) {
                    model.moveSection(id: id, to: model.spec.sections.count)
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
        }
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
