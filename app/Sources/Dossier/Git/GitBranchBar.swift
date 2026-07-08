import SwiftUI

// The explorer's bottom status strip — the current git branch in VS Code's
// bottom-left spot. Click it for the branch quick-pick; hidden entirely when
// the open folder isn't a git work tree. The trailing `*` mirrors VS Code's
// uncommitted-changes marker.
struct GitBranchBar: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var hovering = false

    var body: some View {
        if let git = model.gitStatus {
            VStack(spacing: 0) {
                Divider().overlay(Theme.Colors.hairline)
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                            .foregroundStyle(Theme.Colors.mute)
                        Text(git.displayName + (git.isDirty ? "*" : ""))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Theme.Spacing.xs)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.Colors.mute)
                            .opacity(hovering ? 1 : 0)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(hovering ? Theme.Colors.hairlineSoft : Color.clear)
                .onHover { hovering = $0 }
                .animation(Theme.Motion.snappy, value: hovering)
                .help("Switch git branch")
                .popover(isPresented: $showPicker, arrowEdge: .top) {
                    BranchPickerPopover()
                }
            }
        }
    }
}

// MARK: - Branch quick-pick

// The VS Code-style picker: a search field over the branch list, arrow keys +
// Enter to pick, checkmark on the current branch, local branches first (most
// recently committed on top), then a "Remotes" group. Typing a name no branch
// has offers to create it. Same keyboard shape as FilePickerPopover.
struct BranchPickerPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    // Index of the keyboard-highlighted row in `items`. Arrow keys move it,
    // Enter picks it; it snaps back to the top match as the query changes.
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    /// One pickable row: an existing branch, or the create-branch offer.
    private enum Item: Identifiable {
        case branch(GitBranch)
        case create(String)
        var id: String {
            switch self {
            case .branch(let branch): return branch.id
            case .create(let name):   return "create:" + name
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Switch branch")
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)

            SearchField(text: $search, placeholder: "Find or create a branch",
                        focus: $searchFocused)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
                // Enter validates the highlighted row, so the keyboard alone
                // can switch (or create).
                .onSubmit { pickSelected() }

            Divider().overlay(Theme.Colors.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if items.isEmpty {
                            Text("No branches match")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.mute)
                                .padding(Theme.Spacing.md)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == firstRemoteIndex {
                                    groupLabel("Remotes")
                                }
                                row(item, selected: index == selection)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(Theme.Spacing.xs)
                }
                .onChange(of: selection) { _, new in
                    guard items.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(items[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 300, height: 340)
        .background(Theme.Colors.surface)
        // Move the highlight with the arrow keys while focus stays in the
        // search field; clamp to the current result list.
        .onKeyPress(.downArrow) {
            guard !items.isEmpty else { return .ignored }
            selection = min(selection + 1, items.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !items.isEmpty else { return .ignored }
            selection = max(selection - 1, 0)
            return .handled
        }
        // A changing query reshuffles results, so snap the highlight back to
        // the top match each time the text changes.
        .onChange(of: search) { selection = 0 }
        // Esc closes the picker. With the search field focused the popover
        // won't dismiss itself — the field editor swallows the cancel — so
        // catch the key on its way through the SwiftUI hierarchy.
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            // The snapshot may be stale (it refreshes on FS events, not on a
            // clock) — take a fresh one the moment the picker opens.
            model.refreshGitStatus()
            // Focus the field after the popover settles so typing and arrow
            // navigation work immediately.
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ item: Item, selected: Bool) -> some View {
        switch item {
        case .branch(let branch):
            BranchPickRow(branch: branch,
                          isCurrent: isCurrent(branch),
                          selected: selected) { pick(item) }
        case .create(let name):
            CreateBranchRow(name: name, selected: selected) { pick(item) }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.mute)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xxs)
    }

    // MARK: Data

    private var items: [Item] {
        guard let git = model.gitStatus else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces)
        let matches: (GitBranch) -> Bool = {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        var items: [Item] = git.localBranches.filter(matches).map(Item.branch)
            + git.remoteBranches.filter(matches).map(Item.branch)
        // Typing a name no branch has offers to create it at HEAD (VS Code's
        // "create new branch" pick). Skip names git would obviously refuse.
        if !query.isEmpty, !query.contains(" "),
           !git.localBranches.contains(where: { $0.name == query }),
           !git.remoteBranches.contains(where: { $0.name == query || $0.localName == query }) {
            items.append(.create(query))
        }
        return items
    }

    /// Where the "Remotes" group label goes: before the first remote row.
    private var firstRemoteIndex: Int? {
        items.firstIndex {
            if case .branch(let branch) = $0 { return branch.isRemote }
            return false
        }
    }

    private func isCurrent(_ branch: GitBranch) -> Bool {
        !branch.isRemote && branch.name == model.gitStatus?.currentBranch
    }

    // MARK: Picking

    /// Pick whichever row is highlighted, falling back to the top match.
    private func pickSelected() {
        guard !items.isEmpty else { return }
        pick(items[items.indices.contains(selection) ? selection : 0])
    }

    private func pick(_ item: Item) {
        dismiss()
        switch item {
        case .branch(let branch):
            // Re-picking the current branch is a no-op, not a checkout.
            guard !isCurrent(branch) else { return }
            model.switchBranch(to: branch)
        case .create(let name):
            model.createBranch(named: name)
        }
    }
}

// MARK: - Row views

private struct BranchPickRow: View {
    let branch: GitBranch
    let isCurrent: Bool
    var selected: Bool = false
    let onPick: () -> Void
    @State private var hovering = false

    // Keyboard selection wins over hover so the highlight reads clearly while
    // arrow-navigating; hover keeps its subtler tint for the mouse.
    private var rowFill: Color {
        if selected { return Theme.Colors.accentSoft }
        return hovering ? Theme.Colors.hairlineSoft : Color.clear
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                    .imageScale(.small)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.mute)
                Text(branch.name)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(isCurrent ? Theme.Colors.accentText : Theme.Colors.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .foregroundStyle(Theme.Colors.accentText)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowFill,
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CreateBranchRow: View {
    let name: String
    var selected: Bool = false
    let onPick: () -> Void
    @State private var hovering = false

    private var rowFill: Color {
        if selected { return Theme.Colors.accentSoft }
        return hovering ? Theme.Colors.hairlineSoft : Color.clear
    }

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "plus.circle")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.accentText)
                Text("Create branch “\(name)”")
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.accentText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowFill,
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
