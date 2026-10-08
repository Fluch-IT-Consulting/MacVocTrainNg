import AppKit
import UniformTypeIdentifiers
import VocabCore

/// "Import Cards…": reads cards from a CSV or TSV file into a preview, from which
/// the chosen cards are appended to the open deck.
@MainActor
enum CardImport {
    /// The cards of a file, before they are added to the deck.
    @Observable
    final class Preview: Identifiable {
        let fileName: String
        let candidates: [CardImporter.Candidate]
        let skippedRows: Int
        /// The cards to add; duplicates start out unselected.
        var selection: Set<Card.ID>

        init(fileName: String, result: CardImporter.Result) {
            self.fileName = fileName
            candidates = result.candidates
            skippedRows = result.skippedRows
            selection = Set(result.candidates.filter { $0.duplicate == nil }.map(\.id))
        }

        /// The selected cards in file order.
        var selectedCards: [Card] {
            candidates.filter { selection.contains($0.id) }.map(\.card)
        }
    }

    /// Asks for a file and reads it; `nil` if the user cancels or the file has no cards.
    static func chooseFile(existing: [Card], created: Date) -> Preview? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.delimitedText, .plainText]
        openPanel.allowsMultipleSelection = false
        openPanel.message = String(localized: "Choose a CSV or TSV file with a question, an answer and an optional hint per row.")
        openPanel.prompt = String(localized: "Import")
        guard openPanel.runModal() == .OK, let source = openPanel.url else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            showError(error.localizedDescription)
            return nil
        }
        let preview = preview(of: data, fileName: source.lastPathComponent, existing: existing, created: created)
        guard !preview.candidates.isEmpty else {
            showError(String(localized: "“\(source.lastPathComponent)” contains no rows with a question and an answer."))
            return nil
        }
        return preview
    }

    static func preview(of data: Data, fileName: String, existing: [Card], created: Date) -> Preview {
        let rows = DelimitedText.decode(data).rows
        let result = CardImporter.candidates(from: rows, existing: existing, isHeader: isHeader, created: created)
        return Preview(fileName: fileName, result: result)
    }

    /// Whether `row` starts with the column titles of an export, in any language of
    /// the app, so files exported in another language are recognised as well.
    nonisolated static func isHeader(_ row: [String]) -> Bool {
        guard row.count >= 2 else { return false }
        func matches(_ field: String, _ key: String) -> Bool {
            let field = field.trimmingCharacters(in: .whitespacesAndNewlines)
            return titles(for: key).contains { $0.compare(field, options: .caseInsensitive) == .orderedSame }
        }
        return matches(row[0], "Question") && matches(row[1], "Answer")
    }

    /// The key itself, which is the English title, and its translations.
    private nonisolated static func titles(for key: String) -> [String] {
        let translations = Bundle.main.localizations.compactMap { language in
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        .map { $0.localizedString(forKey: key, value: key, table: nil) }
        return [key] + translations
    }

    private static func showError(_ message: String) {
        NSAlert.showWarning(String(localized: "Import failed"), message: message)
    }
}
