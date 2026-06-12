import SwiftUI

// The floating in-app file preview. Opened from the explorer's magnifier (hover
// a file row) or a file section's magnifier in the builder. One panel at a
// time: previewing another file repoints the same panel rather than stacking.

/// What the panel is showing — the repo-relative path plus its resolved URL,
/// and where the opening click landed (window coordinates, top-left origin)
/// so the panel can appear next to it rather than dead-center.
struct FilePreviewRequest: Equatable {
    let relativePath: String
    let url: URL
    let anchor: CGPoint?
    var name: String { url.lastPathComponent }
}

/// Hosts the panel over the project view and places it next to the click that
/// opened it, clamped so it never pokes outside the window. The transparent
/// remainder of the overlay passes clicks through to the panes beneath.
struct FilePreviewOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            if let request = model.filePreview {
                let position = position(for: request, in: geo)
                FilePreviewPanel(request: request)
                    .position(position)
                    // Grow out of where it lands, not the window center.
                    .transition(.scale(scale: 0.94, anchor: UnitPoint(
                        x: position.x / max(geo.size.width, 1),
                        y: position.y / max(geo.size.height, 1)))
                        .combined(with: .opacity))
            }
        }
    }

    /// The panel's center: top-leading corner just below-right of the click,
    /// pulled back inside the overlay when the click is near an edge.
    private func position(for request: FilePreviewRequest,
                          in geo: GeometryProxy) -> CGPoint {
        let bounds = geo.size
        let size = FilePreviewPanel.size
        guard let anchor = request.anchor else {
            return CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        }
        // The anchor is in window points; this overlay lives inside the zoom
        // transform, so map through the rendered-vs-laid-out scale.
        let global = geo.frame(in: .global)
        let scale = max(global.width / max(bounds.width, 1), 0.01)
        let local = CGPoint(x: (anchor.x - global.minX) / scale,
                            y: (anchor.y - global.minY) / scale)
        let margin = Theme.Spacing.md
        var origin = CGPoint(x: local.x + 14, y: local.y + 10)
        origin.x = max(min(origin.x, bounds.width - size.width - margin), margin)
        origin.y = max(min(origin.y, bounds.height - size.height - margin), margin)
        return CGPoint(x: origin.x + size.width / 2,
                       y: origin.y + size.height / 2)
    }
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

    static let size = CGSize(width: 560, height: 400)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Colors.hairline)
            body(for: content)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.Colors.surfaceCard,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .hairlineBorder(Theme.Radius.lg, color: Theme.Colors.hairlineStrong)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 10)
        .offset(restingOffset + dragOffset)
        .onExitCommand { model.closeFilePreview() }
        .task(id: request.url) { await load() }
        // Repointed at another click: the new anchor decides the position, so
        // any leftover drag from the previous spot would land it off-target.
        .onChange(of: request) {
            withAnimation(Theme.Motion.smooth) { restingOffset = .zero }
        }
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
