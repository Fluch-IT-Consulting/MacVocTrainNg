import Foundation
import VocabCore

/// One row of the card table, with plain sortable values.
struct CardRow: Identifiable {
    var id: Card.ID
    var position: Int
    var question: String
    var answer: String
    var remark: String
    var category: MaturityCategory
    var categoryRank: Int
    var due: Date?
    /// New cards first, then by due date.
    var dueSortKey: Double

    init(card: Card, position: Int) {
        id = card.id
        self.position = position
        question = card.question
        answer = card.answer
        remark = card.remark
        category = MaturityCategory(card: card)
        categoryRank = StabilityBins.bin(for: card)
        due = card.memory?.due
        dueSortKey = card.memory?.due.timeIntervalSinceReferenceDate ?? -.infinity
    }
}

/// The rows of the card table, sorted and filtered by a search.
///
/// Keeps the rows, the search index and the sorted order between view updates and
/// rebuilds them only when the cards or the sort order change, so typing a search
/// or selecting rows stays fast with many cards. It is not observable: the view asks
/// for its rows while it renders.
@MainActor
final class CardTable {
    private var cards: [Card] = []
    private var allRows: [CardRow] = []
    private var index = CardSearchIndex(cards: [])
    private var sorted: (order: [KeyPathComparator<CardRow>], positions: [Int])?
    private var shown: (query: String, rows: [CardRow])?

    func rows(of cards: [Card], sortedBy order: [KeyPathComparator<CardRow>], matching query: String) -> [CardRow] {
        // Cheap while nothing changed: arrays sharing storage compare equal at once.
        if cards != self.cards {
            self.cards = cards
            allRows = cards.enumerated().map { CardRow(card: $1, position: $0) }
            index = CardSearchIndex(cards: cards)
            sorted = nil
        }
        let positions: [Int]
        if let sorted, sorted.order == order {
            positions = sorted.positions
        } else {
            positions = allRows.sorted(using: order).map(\.position)
            sorted = (order, positions)
            shown = nil
        }
        if let shown, shown.query == query {
            return shown.rows
        }
        let rows = index.filter(positions, by: query).map { allRows[$0] }
        shown = (query, rows)
        return rows
    }
}
