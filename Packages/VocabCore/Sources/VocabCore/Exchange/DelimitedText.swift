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

    private static func quoted(_ field: String, delimiter: Delimiter) -> String {
        let needsQuotes = field.contains { $0 == delimiter.rawValue || $0 == "\"" || $0.isNewline }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
