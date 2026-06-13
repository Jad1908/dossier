import SwiftUI

// Right pane — the live preview (DESKTOP_APP_SPEC §6, §8, DESIGN.md §preview-pane).
// Outline by default: each section's envelope with text/tree shown in full and
// `file` bodies collapsed to a summary chip. A toggle reveals the full
// materialized prompt — exactly what Copy/Save emit.
struct PreviewView: View {
    @Environment(AppModel.self) private var model

    enum Mode: Hashable { case outline, full }
    @State private var mode: Mode = Defaults.defaultPreviewMode == "full" ? .full : .outline

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Theme.Colors.hairline)
            content
        }
        .background(Theme.Colors.surface)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            SegmentedControl(
                selection: $mode,
                options: [(Mode.outline, "Outline"), (Mode.full, "Full prompt")])
                .frame(width: 220)
            Spacer()
            // Always mounted, faded via opacity only. Inserting it with a
            // .scale transition animated an AppKit-backed NSProgressIndicator
            // from scale ~0, which made SwiftUI request absurd inverse-scale
            // layer sizes ("Ignoring bogus layer size" — a whole-window draw
            // glitch that read as the screen flashing) every time a render
            // crossed the spinner threshold.
            ProgressView().controlSize(.small)
                .opacity(model.isRendering ? 1 : 0)
            Text(tokenLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
                .contentTransition(.numericText())
        }
        .padding(Theme.Spacing.md)
        // Fade the spinner locally so a slow render reads gently, without pulling
        // the whole preview into an animation transaction on every render.
        .animation(Theme.Motion.snappy, value: model.isRendering)
    }

    private var tokenLabel: String {
        guard let n = model.lastResult?.tokenEstimate else { return "" }
        return "≈ \(n.formatted()) tokens"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let engineError = model.engineError {
            EngineErrorBanner(message: engineError).padding(Theme.Spacing.md)
                .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        } else if let result = model.lastResult, !result.ok {
            ScrollView {
                ErrorBanner(errors: result.errors)
                    .padding(Theme.Spacing.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        } else if let result = model.lastResult {
            ZStack {
                switch mode {
                case .outline:
                    OutlineView(result: result)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .full:
                    FullPromptView(prompt: result.prompt ?? "")
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(Theme.Motion.smooth, value: mode)
        } else {
            Spacer()
        }
    }
}

// MARK: - Outline

private struct OutlineView: View {
    @Environment(AppModel.self) private var model
    let result: ForgeResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(Array(result.sections.enumerated()), id: \.offset) { index, section in
                    OutlineRow(section: section, filePath: filePath(at: index))
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// When the render succeeded, result.sections is 1:1 with spec.sections in
    /// order, so a `file` row can recover its path for the summary chip.
    private func filePath(at index: Int) -> String? {
        guard index < model.spec.sections.count else { return nil }
        return model.spec.sections[index].filePath
    }
}

private struct OutlineRow: View {
    let section: ForgeSection
    let filePath: String?
    @State private var expanded = false       // file chip peek
    @State private var collapsed = false       // text/tree fold (VSCode-style)

    private var isFile: Bool { section.type == "file" }
    private var isFolder: Bool { section.type == "folder" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Envelope line; text/tree/folder rows get a small fold chevron.
            HStack(spacing: Theme.Spacing.xs) {
                if !isFile {
                    Button {
                        withAnimation(Theme.Motion.snappy) { collapsed.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(collapsed ? "Expand" : "Collapse")
                }
                Text("<section name=\"\(section.name)\" type=\"\(section.type)\">"
                     + (collapsed && !isFile ? " … </section>" : ""))
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Colors.mute)
                    .textSelection(.enabled)
            }

            if isFile {
                FileSummaryChip(section: section, path: filePath, expanded: $expanded)
                closingTag
            } else if !collapsed {
                if isFolder {
                    FolderSummary(content: section.content)
                } else {
                    ClampedText(section.content, limit: PreviewLimit.section)
                }
                closingTag
            }
        }
    }

    private var closingTag: some View {
        Text("</section>")
            .font(Theme.Typography.mono)
            .foregroundStyle(Theme.Colors.mute)
    }
}

// MARK: - Folder outline

/// A folder section's body: one collapsible chip per joined file. The engine
/// concatenates files as `## <path>\n<body>` blocks (blank-line separated), so
/// a subheader is a `## ` line at the start or just after a blank line — the
/// exact shape sections.py emits. Copy/Save use the engine's raw content; this
/// re-parse only drives the outline's per-file folds.
private struct FolderSummary: View {
    let content: String

    private var files: [FolderFile] { FolderFile.parse(content) }

    var body: some View {
        if files.isEmpty {
            Text("(empty folder)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.mute)
                ForEach(files) { file in
                    FolderFileChip(file: file)
                }
            }
        }
    }
}

/// One parsed file within a folder section: its path subheader and body (empty
/// for the "presence only" files — binaries and empty files the engine notes
/// by name without inlining).
private struct FolderFile: Identifiable {
    let id = UUID()
    let path: String
    let body: String

    var inlined: Bool { !body.isEmpty }

    static func parse(_ content: String) -> [FolderFile] {
        var files: [FolderFile] = []
        var path: String?
        var bodyLines: [String] = []
        var afterBlank = true       // start-of-content counts as "after a blank"

        func flush() {
            guard let path else { return }
            var lines = bodyLines
            while lines.last?.isEmpty == true { lines.removeLast() }
            files.append(FolderFile(path: path, body: lines.joined(separator: "\n")))
        }

        for line in content.components(separatedBy: "\n") {
            if afterBlank, line.hasPrefix("## ") {
                flush()
                path = String(line.dropFirst(3))
                bodyLines = []
            } else if path != nil {
                bodyLines.append(line)
            }
            afterBlank = line.isEmpty
        }
        flush()
        return files
    }
}

/// A single file's row in the folder outline: a collapsible summary chip that
/// mirrors FileSummaryChip. Inlined files expand to their content; presence-only
/// files (binaries) show a muted "not inlined" note and don't expand.
private struct FolderFileChip: View {
    let file: FolderFile
    @State private var expanded = false

    private var lineCount: Int {
        file.body.split(separator: "\n", omittingEmptySubsequences: false).count
    }
    private var byteCount: Int { file.body.utf8.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                guard file.inlined else { return }
                withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: file.inlined
                          ? (expanded ? "chevron.down" : "chevron.right")
                          : "minus")
                        .font(.system(size: 9, weight: .semibold))
                    Text(summary)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
            .surfaceTile(fill: Theme.Colors.surfaceElevated, radius: Theme.Radius.sm)
            .disabled(!file.inlined)

            if expanded, file.inlined {
                ClampedText(file.body, limit: PreviewLimit.section)
                    .padding(Theme.Spacing.sm)
                    .surfaceTile(fill: Theme.Colors.surface, radius: Theme.Radius.sm)
            }
        }
    }

    private var summary: String {
        guard file.inlined else { return "\(file.path) · not inlined" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount),
                                              countStyle: .file)
        return "\(file.path) · \(lineCount) lines · ~\(size)"
    }
}

/// A collapsed file body in the outline (DESIGN.md §file-summary-chip).
private struct FileSummaryChip: View {
    let section: ForgeSection
    let path: String?
    @Binding var expanded: Bool

    private var lineCount: Int { section.content.split(separator: "\n", omittingEmptySubsequences: false).count }
    private var byteCount: Int { section.content.utf8.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(summary)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
            .surfaceTile(fill: Theme.Colors.surfaceElevated, radius: Theme.Radius.sm)

            if expanded {
                ClampedText(section.content, limit: PreviewLimit.section)
                    .padding(Theme.Spacing.sm)
                    .surfaceTile(fill: Theme.Colors.surface, radius: Theme.Radius.sm)
            }
        }
    }

    private var summary: String {
        let name = path ?? section.name
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount),
                                              countStyle: .file)
        return "\(name) · \(lineCount) lines · ~\(size)"
    }
}

// MARK: - Full prompt

private struct FullPromptView: View {
    let prompt: String
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ClampedText(prompt, limit: PreviewLimit.full)
                .padding(Theme.Spacing.md)
        }
    }
}

// MARK: - Clamped text

/// Caps how much text the preview lays out. SwiftUI's `Text` is quadratic-ish on
/// very long strings, so a multi-megabyte render (e.g. a `tree` section walking
/// an un-ignored build folder) would freeze the UI. Copy/Save are unaffected —
/// they emit the engine's full `prompt`, never this clamped display copy.
enum PreviewLimit {
    static let section = 20_000
    static let full = 80_000
}

struct ClampedText: View {
    let text: String
    let limit: Int
    init(_ text: String, limit: Int) { self.text = text; self.limit = limit }

    private var clamped: String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
    private var truncated: Bool { text.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(clamped)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if truncated {
                Text("… preview truncated (\(text.count.formatted()) chars). "
                     + "Copy and Save still emit the full prompt.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
    }
}

// MARK: - Banners

/// Spec render errors (DESIGN.md §error-banner): per-error, naming the section.
private struct ErrorBanner: View {
    let errors: [ForgeError]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Spec has \(errors.count) error\(errors.count == 1 ? "" : "s")",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.bodyStrong)
                .foregroundStyle(Theme.Colors.error)
            ForEach(errors) { error in
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    if let section = error.section {
                        StatusBadge(tone: .error, text: section)
                    }
                    Text(error.message)
                        .font(Theme.Typography.bodyMd)
                        .foregroundStyle(Theme.Colors.error)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.errorSoft,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Colors.error.opacity(0.4), lineWidth: 1))
    }
}

/// Engine failure (binary missing / non-zero exit / unparseable) — distinct
/// from spec errors; uses the warning tone and shows captured stderr (§8).
private struct EngineErrorBanner: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Engine error", systemImage: "bolt.trianglebadge.exclamationmark")
                .font(Theme.Typography.bodyStrong)
                .foregroundStyle(Theme.Colors.warning)
            Text(message)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.warningSoft,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Colors.warning.opacity(0.4), lineWidth: 1))
    }
}
