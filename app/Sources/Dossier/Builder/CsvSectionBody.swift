import SwiftUI

// The csv section body (spec.py CsvSection): a head extractor over a tabular
// file. Scope is "first N rows" (the default peek) or the whole file, and the
// columns picker narrows the table to named header columns — so a dataset can
// inform a prompt without drowning it.
struct CsvSectionBody: View {
    @Environment(AppModel.self) private var model
    @Binding var binding: SpecSection
    @State private var showPicker = false
    @State private var showColumns = false

    private var path: String {
        if case let .csv(p, _, _, _) = binding.kind { return p }
        return ""
    }
    private var rows: Int {
        if case let .csv(_, r, _, _) = binding.kind { return r }
        return SectionKind.defaultCSVRows
    }
    private var columns: [String] {
        if case let .csv(_, _, c, _) = binding.kind { return c }
        return []
    }
    private var external: Bool { binding.kind.isExternal }
    /// The file's location: absolute for an external csv, else under the project.
    private var fileURL: URL? {
        external ? URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                 : model.projectURL?.appendingPathComponent(path)
    }
    private var wholeFile: Bool { rows == -1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            pathRow

            SegmentedControl(
                selection: Binding(
                    get: { wholeFile },
                    set: { whole in
                        set(rows: whole ? -1 : SectionKind.defaultCSVRows)
                    }),
                options: [(false, "First rows"), (true, "Whole file")])

            if !wholeFile {
                HStack(spacing: Theme.Spacing.md) {
                    Stepper(value: Binding(get: { max(rows, 1) },
                                           set: { set(rows: $0) }),
                            in: 1...9999) {
                        Text(headerOnly ? "Rows: —" : "Rows: \(rows)")
                            .font(Theme.Typography.bodyMd)
                            .foregroundStyle(headerOnly ? Theme.Colors.ash
                                                        : Theme.Colors.body)
                    }
                    .disabled(headerOnly)

                    Toggle(isOn: Binding(
                        get: { headerOnly },
                        set: { set(rows: $0 ? 0 : SectionKind.defaultCSVRows) })) {
                        Text("Header only")
                            .font(Theme.Typography.bodyMd)
                            .foregroundStyle(Theme.Colors.body)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.Colors.accentPrimary)
                    .help("Take just the first line — the column names")
                }
            }

            Button {
                showColumns = true
            } label: {
                Label(columnsLabel, systemImage: "checklist")
            }
            .buttonStyle(TertiaryButtonStyle())
            .fixedSize()
            .help("Choose which columns to keep")
            .popover(isPresented: $showColumns, arrowEdge: .bottom) {
                CsvColumnsPopover(url: fileURL, section: $binding)
            }
        }
        .animation(Theme.Motion.smooth, value: wholeFile)
        .animation(Theme.Motion.snappy, value: headerOnly)
    }

    /// rows == 0 — emit just the header line (the column names).
    private var headerOnly: Bool { rows == 0 }

    private var columnsLabel: String {
        columns.isEmpty ? "Columns: all" : "Columns: \(columns.count)"
    }

    // The header is always kept; `rows` counts data rows below it.
    private func set(rows: Int? = nil, columns: [String]? = nil) {
        binding.kind = .csv(path: path,
                            rows: rows ?? self.rows,
                            columns: columns ?? self.columns,
                            external: external)
    }

    // MARK: - Path row (mirrors the file section's)

    private var pathRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "tablecells").imageScale(.small)
                .foregroundStyle(Theme.Colors.mute)
            Text(path)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Colors.mute)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            Button {
                model.previewFile(relativePath: path, external: external)
            } label: {
                Image(systemName: "magnifyingglass").imageScale(.small)
            }
            .buttonStyle(IconButtonStyle())
            .help("Preview this file")
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
                    model.setFileSection(binding.id, relativePath: rel)
                    showPicker = false
                } onPickExternal: { abs in
                    model.setFileSection(binding.id, relativePath: abs, external: true)
                    showPicker = false
                }
                .environment(model)
            }
        }
    }
}

// MARK: - Columns picker

/// Checkbox per header column, read from the file itself. An empty stored
/// selection means "all columns" (the engine's default), so the picker shows
/// everything checked; storing [] again the moment all boxes are checked keeps
/// the TOML clean. The last checked column can't be unchecked — an empty pick
/// would silently mean "all" again, which is exactly the opposite.
///
/// Works on a live Binding to the section, never a captured snapshot: popover
/// content closures don't reliably re-evaluate when the presenter updates, and
/// a captured selection went stale after the first toggle (every later toggle
/// recomputed from the original state).
private struct CsvColumnsPopover: View {
    let url: URL?
    @Binding var section: SpecSection

    @State private var header: [String]?   // nil while loading

    private var selected: [String] {
        if case let .csv(_, _, c, _) = section.kind { return c }
        return []
    }

    private func apply(_ columns: [String]) {
        if case let .csv(path, rows, _, external) = section.kind {
            section.kind = .csv(path: path, rows: rows, columns: columns, external: external)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Columns")
                    .font(Theme.Typography.headingSm)
                    .foregroundStyle(Theme.Colors.ink)
                Spacer()
                if let names = header, !names.isEmpty {
                    Text(selected.isEmpty ? "all \(names.count)"
                                          : "\(selected.count) of \(names.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.mute)
                }
            }
            content
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 260)
        .task { await load() }
    }

    /// One checkbox row's slice of the list height (13pt label + spacing).
    private static let rowHeight: CGFloat = 24
    private static let maxListHeight: CGFloat = 264   // ~11 rows, then scroll

    @ViewBuilder
    private var content: some View {
        switch header {
        case .none:
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 60)
        case .some(let names) where names.isEmpty:
            Text("Couldn't read a header row from this file.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        case .some(let names):
            // The list gets an explicit height: a popover sizes to its
            // content's IDEAL height, and a ScrollView's ideal height along
            // its scroll axis is ~zero — left to negotiate, the whole list
            // collapsed to a sliver.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        Toggle(isOn: toggleBinding(for: name, header: names)) {
                            Text(name.isEmpty ? "(unnamed)" : name)
                                .font(Theme.Typography.bodyMd)
                                .foregroundStyle(Theme.Colors.body)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(CGFloat(names.count) * Self.rowHeight,
                               Self.maxListHeight))
            Button("Select all") { apply([]) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(selected.isEmpty)
        }
    }

    private func toggleBinding(for name: String, header: [String]) -> Binding<Bool> {
        Binding(
            get: { selected.isEmpty || selected.contains(name) },
            set: { include in
                var picks = Set(selected.isEmpty ? header : selected)
                if include { picks.insert(name) } else { picks.remove(name) }
                guard !picks.isEmpty else { return }   // keep at least one
                // Back to the full set? Store "all" canonically as empty.
                apply(picks == Set(header) ? [] : header.filter(picks.contains))
            })
    }

    private func load() async {
        guard let url else { header = []; return }
        header = await Task.detached(priority: .userInitiated) {
            CSVHeader.columns(of: url)
        }.value
    }
}

// (CSVHeader — the robust header reader the columns picker uses — lives in
// Support/CSVHeader.swift.)
