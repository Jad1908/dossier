import SwiftUI

// The floating in-app file preview. Opened from the explorer's magnifier (hover
// a file row) or a file section's magnifier in the builder. One panel at a
// time: previewing another file repoints the same panel rather than stacking.

/// What the panel is showing — the repo-relative path plus its resolved URL.
struct FilePreviewRequest: Equatable {
    let relativePath: String
    let url: URL
    var name: String { url.lastPathComponent }
}

/// A small floating window embedded in the app: a card that hovers over the
/// project view, draggable by its header, scrollable both ways so wide and
/// long files stay readable without wrapping.
struct FilePreviewPanel: View {
    @Environment(AppModel.self) private var model
    let request: FilePreviewRequest

    @State private var content: Content = .loading
    /// Where the user has dragged the panel, persisted across previews so the
    /// "window" stays put when it's repointed at another file.
    @State private var restingOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private enum Content: Equatable {
        case loading
        case text(String, truncated: Bool)
        case unreadable(String)
    }

    /// Beyond this the preview shows a prefix — it's a peek, not an editor.
    private static let byteLimit = 1 << 20   // 1 MiB

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            body(for: content)
        }
        .frame(width: 560, height: 400)
        .background(Theme.Colors.surfaceCard,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .hairlineBorder(Theme.Radius.lg, color: Theme.Colors.hairlineStrong)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
        .offset(restingOffset + dragOffset)
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .onExitCommand { model.closeFilePreview() }
        .task(id: request.url) { await load() }
    }

    // MARK: - Header (the drag handle)

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Theme.Colors.mute)
            Text(request.name)
                .font(Theme.Typography.bodyStrong)
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
            Text(request.relativePath)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            Button {
                model.closeFilePreview()
            } label: {
                Image(systemName: "xmark.circle.fill").imageScale(.small)
            }
            .buttonStyle(IconButtonStyle())
            .help("Close preview")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceElevated)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    restingOffset = restingOffset + value.translation
                }
        )
    }

    // MARK: - Body by load state

    @ViewBuilder
    private func body(for content: Content) -> some View {
        switch content {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unreadable(message):
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(Theme.Colors.mute)
                Text(message)
                    .font(Theme.Typography.bodyMd)
                    .foregroundStyle(Theme.Colors.mute)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .text(text, truncated):
            VStack(spacing: 0) {
                // Both axes: long files scroll down, wide lines scroll right —
                // nothing wraps, so code reads as written.
                ScrollView([.vertical, .horizontal]) {
                    Text(text.isEmpty ? "(empty file)" : text)
                        .font(Theme.Typography.mono)
                        .foregroundStyle(text.isEmpty ? Theme.Colors.mute
                                                      : Theme.Colors.body)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }
                if truncated {
                    Divider().overlay(Theme.Colors.hairline)
                    Text("Preview truncated — showing the first 1 MB.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.surfaceElevated)
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        content = .loading
        let url = request.url
        let limit = Self.byteLimit
        let loaded: Content = await Task.detached(priority: .userInitiated) {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return .unreadable("Couldn't read this file.")
            }
            defer { try? handle.close() }
            guard var data = try? handle.read(upToCount: limit + 1) else {
                return .unreadable("Couldn't read this file.")
            }
            let truncated = data.count > limit
            if truncated { data = data.prefix(limit) }
            // A byte cap can land mid-character; shave up to three trailing
            // bytes before declaring the file binary.
            for trim in 0...3 {
                if let text = String(data: data.dropLast(trim), encoding: .utf8) {
                    return .text(text, truncated: truncated)
                }
            }
            return .unreadable("This file isn't text — nothing to preview.")
        }.value
        withAnimation(Theme.Motion.smooth) { content = loaded }
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}
