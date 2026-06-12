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
        if case let .csv(p, _, _) = binding.kind { return p }
        return ""
    }
    private var rows: Int {
        if case let .csv(_, r, _) = binding.kind { return r }
        return SectionKind.defaultCSVRows
    }
    private var columns: [String] {
        if case let .csv(_, _, c) = binding.kind { return c }
        return []
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
                CsvColumnsPopover(
                    url: model.projectURL?.appendingPathComponent(path),
                    selected: columns,
                    apply: { set(columns: $0) })
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
                            columns: columns ?? self.columns)
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
                model.previewFile(relativePath: path)
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
private struct CsvColumnsPopover: View {
    let url: URL?
    let selected: [String]
    let apply: ([String]) -> Void

    @State private var header: [String]?   // nil while loading

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Columns")
                .font(Theme.Typography.headingSm)
                .foregroundStyle(Theme.Colors.ink)
            content
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 240)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch header {
        case .none:
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity)
        case .some(let names) where names.isEmpty:
            Text("Couldn't read a header row from this file.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.mute)
        case .some(let names):
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
            }
            .frame(maxHeight: 260)
            if !selected.isEmpty {
                Button("Select all") { apply([]) }
                    .buttonStyle(SecondaryButtonStyle())
            }
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

// MARK: - Header parsing

/// Reads just the first record of a csv file — the column names the picker
/// offers. Robust to the exports seen in the wild: the delimiter is sniffed
/// (comma, semicolon, tab, pipe — Excel writes `;` in many locales), a UTF-8
/// BOM is tolerated, fields are quote-aware ("" escapes, embedded newlines),
/// and names are whitespace-trimmed — matching how the engine reads the file,
/// so picked names line up with what it filters on. Capped at 64 KB: a header
/// longer than that isn't a header.
enum CSVHeader {
    private static let candidateDelimiters: [Character] = [",", ";", "\t", "|"]

    static func columns(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 1 << 16),
              !data.isEmpty
        else { return [] }
        try? handle.close()
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let record = firstRecord(of: text)
        return parse(record: record, delimiter: sniffDelimiter(in: record))
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Everything up to the first record break — a newline outside quotes.
    private static func firstRecord(of text: String) -> Substring {
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\"" {
                // An escaped "" toggles twice — net unchanged, as it should be.
                inQuotes.toggle()
            } else if !inQuotes, ch == "\n" || ch == "\r" {
                return text[text.startIndex..<i]
            }
            i = text.index(after: i)
        }
        return text[...]
    }

    /// The candidate that splits the record the most, quoted runs excluded.
    /// Ties keep candidate order, so a lone comma still beats a lone pipe.
    private static func sniffDelimiter(in record: Substring) -> Character {
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for ch in record {
            if ch == "\"" { inQuotes.toggle() }
            else if !inQuotes, candidateDelimiters.contains(ch) {
                counts[ch, default: 0] += 1
            }
        }
        return candidateDelimiters.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
            ?? ","
    }

    private static func parse(record: Substring,
                              delimiter: Character) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var i = record.startIndex
        while i < record.endIndex {
            let ch = record[i]
            if inQuotes {
                if ch == "\"" {
                    let next = record.index(after: i)
                    if next < record.endIndex, record[next] == "\"" {
                        field.append("\"")   // escaped quote
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                fields.append(field); field = ""
            } else {
                field.append(ch)
            }
            i = record.index(after: i)
        }
        fields.append(field)
        return fields
    }
}
