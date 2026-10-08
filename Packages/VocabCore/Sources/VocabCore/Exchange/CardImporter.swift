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
        /// An earlier card of the file, with this question and answer, has the same question.
        case inFile(question: String, answer: String)
    }

    public struct Candidate: Identifiable, Sendable {
        public var card: Card
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
        // The first card of each question in the file.
        var inFile: [String: Card] = [:]

        for (index, row) in rows.enumerated() {
            if index == 0, isHeader(row) { continue }
            guard row.count >= 2, let text = CardText(question: row[0], answer: row[1], hint: row.count > 2 ? row[2] : "") else {
                result.skippedRows += 1
                continue
            }
            let card = Card(text: text, created: created)
            let key = CardText.key(forQuestion: card.question)
            let duplicate: Duplicate? = inDeck.contains(key) ? .inDeck : inFile[key].map { .inFile(question: $0.question, answer: $0.answer) }
            inFile[key] = inFile[key] ?? card
            result.candidates.append(Candidate(card: card, duplicate: duplicate))
        }
        return result
    }
}
