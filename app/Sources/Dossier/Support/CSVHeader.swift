import Foundation

/// Reads the header (column names) of a delimited text file — what the csv
/// section's columns picker offers. Robust to the exports seen in the wild:
/// a UTF-8 BOM, \r / \r\n / \n record breaks, quoted fields ("" escapes,
/// embedded delimiters and newlines), and any of comma / semicolon / tab /
/// pipe as the delimiter.
///
/// The delimiter is sniffed by structure, with the SAME algorithm as the
/// engine (sections.py `_sniff_delimiter`): parse a sample with each
/// candidate and prefer the split that rows agree on (consistency first,
/// then width) — so the names picked here always match what the engine
/// filters on. Reads at most 64 KB; a header needing more isn't a header.
enum CSVHeader {
    /// Priority order for ties — a lone comma beats a lone pipe.
    static let candidateDelimiters: [Character] = [",", ";", "\t", "|"]

    private static let byteLimit = 1 << 16
    private static let sampleRecords = 30

    static func columns(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: byteLimit),
              !data.isEmpty
        else { return [] }
        try? handle.close()

        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var records = splitRecords(text, limit: sampleRecords)
        if data.count == byteLimit, records.count > 1 {
            records.removeLast()   // the cut may have split a record
        }
        guard let first = records.first else { return [] }
        return parse(record: first, delimiter: sniffDelimiter(in: records))
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Record splitting (delimiter-independent)

    /// The sample's records: quote-aware, so newlines inside quoted fields
    /// don't break a record; blank lines are skipped.
    static func splitRecords(_ text: String, limit: Int) -> [Substring] {
        var records: [Substring] = []
        var inQuotes = false
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex, records.count < limit {
            let ch = text[i]
            if ch == "\"" {
                // An escaped "" toggles twice — net unchanged, as it should be.
                inQuotes.toggle()
            } else if !inQuotes, ch == "\n" || ch == "\r" {
                if start < i { records.append(text[start..<i]) }
                start = text.index(after: i)
            }
            i = text.index(after: i)
        }
        if records.count < limit, start < i {
            records.append(text[start..<i])
        }
        return records
    }

    // MARK: - Delimiter sniffing (mirror of the engine's)

    static func sniffDelimiter(in records: [Substring]) -> Character {
        var best: Character = ","
        var bestKey: (consistency: Double, cols: Int) = (0, 0)
        for cand in candidateDelimiters {
            let widths = records.map { parse(record: $0, delimiter: cand).count }
            guard let cols = widths.first, cols >= 2 else { continue }
            let matching = widths.filter { $0 == cols }.count
            let key = (Double(matching) / Double(widths.count), cols)
            if key.0 > bestKey.consistency
                || (key.0 == bestKey.consistency && key.1 > bestKey.cols) {
                best = cand
                bestKey = key
            }
        }
        return best
    }

    // MARK: - One-record field parsing

    static func parse(record: Substring, delimiter: Character) -> [String] {
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
