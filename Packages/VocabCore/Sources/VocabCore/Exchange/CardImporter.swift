import Foundation

/// Turns the rows of a table (see `DelimitedText`) into new cards for a deck.
///
/// The columns are question, answer and optional hint; further columns, such as the
/// learning state of an export, are ignored. Fields are trimmed. Rows without a
/// question or an answer are skipped.
public enum CardImporter {
    public enum Duplicate: Hashable, Sendable {
        /// The deck already has a card with this question.
        case inDeck
        /// The given, earlier row of the file has this question.
        case inFile(row: Int)
    }

    public struct Candidate: Identifiable, Sendable {
        public var card: Card
        /// Row in the file, counting from 1 and including a header row.
        public var row: Int
        public var duplicate: Duplicate?

        public var id: Card.ID { card.id }
    }

    public struct Result: Sendable {
        public var candidates: [Candidate]
        /// Rows left out because their question or answer is empty.
        public var skippedRows: Int
    }

    /// - Parameters:
    ///   - existing: The cards of the deck, to mark duplicates.
    ///   - isHeader: Whether the first row is a header rather than a card.
    ///   - created: The creation date of the new cards.
    public static func candidates(from rows: [[String]], existing: [Card], isHeader: ([String]) -> Bool, created: Date) -> Result {
        var result = Result(candidates: [], skippedRows: 0)
        let inDeck = Set(existing.map { CardText.key(forQuestion: $0.question) })
        // The first row of each question in the file.
        var inFile: [String: Int] = [:]

        for (index, row) in rows.enumerated() {
            if index == 0, isHeader(row) { continue }
            guard row.count >= 2, let text = CardText(question: row[0], answer: row[1], hint: row.count > 2 ? row[2] : "") else {
                result.skippedRows += 1
                continue
            }
            let card = Card(question: text.question, answer: text.answer, hint: text.hint, created: created)
            let key = CardText.key(forQuestion: card.question)
            let row = index + 1
            let duplicate: Duplicate? = inDeck.contains(key) ? .inDeck : inFile[key].map { .inFile(row: $0) }
            inFile[key] = inFile[key] ?? row
            result.candidates.append(Candidate(card: card, row: row, duplicate: duplicate))
        }
        return result
    }
}
