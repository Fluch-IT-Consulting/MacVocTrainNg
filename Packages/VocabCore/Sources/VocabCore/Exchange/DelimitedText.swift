import Foundation

/// Tables as delimiter-separated text (CSV, TSV), for exchanging cards with
/// spreadsheets and other apps.
public enum DelimitedText {
    public enum Delimiter: Character, CaseIterable, Sendable {
        case comma = ","
        case semicolon = ";"
        case tab = "\t"
    }

    /// The rows as text, following RFC 4180 with the given delimiter: fields
    /// containing the delimiter, a quote or a line break are enclosed in quotes, with
    /// quotes inside doubled. Every row ends with CRLF.
    public static func encode(_ rows: [[String]], delimiter: Delimiter) -> String {
        rows.map { row in
            row.map { quoted($0, delimiter: delimiter) }.joined(separator: String(delimiter.rawValue))
        }
        .joined(separator: "\r\n") + (rows.isEmpty ? "" : "\r\n")
    }

    /// The rows of a text file, with its encoding and delimiter detected.
    ///
    /// The encoding is UTF-16 if the data starts with its byte order mark, otherwise
    /// UTF-8 if the data is valid UTF-8, otherwise Latin-1 (see `text(of:)`). A UTF-8
    /// byte order mark is skipped. See `detectedDelimiter(in:)` for the delimiter.
    /// Empty lines are left out.
    public static func decode(_ data: Data) -> (rows: [[String]], delimiter: Delimiter) {
        let text = self.text(of: data)
        let delimiter = detectedDelimiter(in: text)
        return (parse(text, delimiter: delimiter), delimiter)
    }

    /// Latin-1 is read as Windows-1252, as Excel on Windows writes it: the same
    /// characters, plus € and typographic quotes where Latin-1 has control characters.
    private static func text(of data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
            let text = String(data: data, encoding: .utf16)
        {
            return text
        }
        let utf8 = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        return String(data: utf8, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// The delimiter that splits the first rows most evenly: the one under which the
    /// most of them have the same number of fields, at least two. Ties go to tab,
    /// then semicolon, then comma, as tabs and semicolons rarely appear in vocabulary.
    public static func detectedDelimiter(in text: String) -> Delimiter {
        let sample = String(text.prefix(20_000))
        var best = (delimiter: Delimiter.comma, score: 0)
        for delimiter in [Delimiter.tab, .semicolon, .comma] {
            let counts = parse(sample, delimiter: delimiter).prefix(20).map(\.count).filter { $0 >= 2 }
            let mostCommon = Dictionary(counts.map { ($0, 1) }, uniquingKeysWith: +).values.max() ?? 0
            if mostCommon > best.score {
                best = (delimiter, mostCommon)
            }
        }
        return best.delimiter
    }

    /// Splits `text` into rows and fields following RFC 4180, accepting any line break.
    /// Lenient with malformed input: a quote inside an unquoted field is kept as is,
    /// and text after a closing quote is appended to the field.
    public static func parse(_ text: String, delimiter: Delimiter) -> [[String]] {
        let separator = delimiter.rawValue.unicodeScalars.first!
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var atFieldStart = true
        var scalars = text.unicodeScalars.makeIterator()
        var pending = scalars.next()

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            atFieldStart = true
        }

        func endRow() {
            endField()
            if row != [""] {
                rows.append(row)
            }
            row = []
        }

        while let scalar = pending {
            pending = scalars.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = scalars.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where atFieldStart:
                inQuotes = true
                atFieldStart = false
            case separator:
                endField()
            case "\r":
                if pending == "\n" {
                    pending = scalars.next()
                }
                endRow()
            case "\n":
                endRow()
            default:
                field.append(scalar)
                atFieldStart = false
            }
        }
        if !field.isEmpty || !row.isEmpty || inQuotes {
            endRow()
        }
        return rows
    }

    private static func quoted(_ field: String, delimiter: Delimiter) -> String {
        let needsQuotes = field.contains { $0 == delimiter.rawValue || $0 == "\"" || $0.isNewline }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
