import Foundation
import VocabCore

/// One row of the card table, with plain sortable values.
struct CardRow: Identifiable {
    var id: Card.ID
    var position: Int
    var question: String
    var answer: String
    var hint: String
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
        hint = card.hint
        category = MaturityCategory(card: card)
        categoryRank = StabilityBins.bin(for: card)
        due = card.learningState?.due
        dueSortKey = card.learningState?.due.timeIntervalSinceReferenceDate ?? -.infinity
    }
}

/// The rows of the card table, sorted and filtered by a search.
///
/// Keeps the rows, the search index and the sorted order between view updates, so
/// typing a search or selecting rows stays fast with many cards. When cards change,
/// only the changed and added cards are sorted in again; a full sort happens only
/// when the sort order changes. When only some cards changed in place, as with an
/// edit or a reset of their learning state, only their rows and index entries are
/// built again (#232). It is not observable: the view asks for its rows while it
/// renders.
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
            let oldCards = self.cards
            self.cards = cards
            if let edited = Self.editedPositions(from: oldCards, to: cards) {
                for position in edited {
                    allRows[position] = CardRow(card: cards[position], position: position)
                    index.replace(at: position, with: cards[position])
                }
                sorted = sorted.flatMap { sorted in
                    guard sorted.order == order else { return nil }
                    return (order, reinserted(edited, into: sorted.positions, by: order))
                }
            } else {
                allRows = cards.enumerated().map { CardRow(card: $1, position: $0) }
                index = CardSearchIndex(cards: cards)
                sorted = sorted.flatMap { sorted in
                    guard sorted.order == order else { return nil }
                    return resorted(sorted.positions, by: order, after: oldCards).map { (order, $0) }
                }
            }
            shown = nil
        }
        let positions: [Int]
        if let sorted, sorted.order == order {
            positions = sorted.positions
        } else {
            positions = allRows.indices.sorted { precedes($0, $1, by: order) }
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

    /// The positions of the cards that changed in place, or `nil` if cards were added,
    /// removed or moved.
    private static func editedPositions(from oldCards: [Card], to cards: [Card]) -> [Int]? {
        guard oldCards.count == cards.count else { return nil }
        var edited: [Int] = []
        for position in cards.indices where cards[position] != oldCards[position] {
            guard cards[position].id == oldCards[position].id else { return nil }
            edited.append(position)
        }
        return edited
    }

    /// Takes the cards at `edited` out of `positions`, sorted before they changed, and
    /// inserts them again by binary search. The other cards keep their place.
    private func reinserted(_ edited: [Int], into positions: [Int], by order: [KeyPathComparator<CardRow>]) -> [Int] {
        let editedSet = Set(edited)
        var result = positions.filter { !editedSet.contains($0) }
        for position in edited {
            let slot = result.partitioningIndex { precedes(position, $0, by: order) }
            result.insert(position, at: slot)
        }
        return result
    }

    /// Updates `positions`, sorted for `oldCards`, to the current cards: unchanged
    /// cards keep their relative order, changed and added ones are inserted by binary
    /// search. Returns `nil` if the unchanged cards were reordered, which the document
    /// never does; the caller then sorts from scratch.
    private func resorted(_ positions: [Int], by order: [KeyPathComparator<CardRow>], after oldCards: [Card]) -> [Int]? {
        let newPositions = Dictionary(cards.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var newPositionOfOld = [Int?](repeating: nil, count: oldCards.count)
        var isUnchanged = [Bool](repeating: false, count: cards.count)
        var previous = -1
        for (oldPosition, card) in oldCards.enumerated() {
            guard let position = newPositions[card.id], cards[position] == card else { continue }
            guard position > previous else { return nil }
            previous = position
            newPositionOfOld[oldPosition] = position
            isUnchanged[position] = true
        }
        // Insertions and removals shift positions, but not the relative order of the
        // cards that stay, so neither does the tie-break by position.
        var result = positions.compactMap { newPositionOfOld[$0] }
        for position in cards.indices where !isUnchanged[position] {
            let slot = result.partitioningIndex { precedes(position, $0, by: order) }
            result.insert(position, at: slot)
        }
        return result
    }

    /// Whether the row at position `lhs` comes before the one at `rhs`. Equal rows keep
    /// their deck order, so sorting from scratch and inserting give the same result.
    private func precedes(_ lhs: Int, _ rhs: Int, by order: [KeyPathComparator<CardRow>]) -> Bool {
        for comparator in order {
            switch comparator.compare(allRows[lhs], allRows[rhs]) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        return lhs < rhs
    }
}

extension Array {
    /// The index of the first element satisfying `belongsAfter`, for an array in
    /// which all elements satisfying it come after those that don't.
    fileprivate func partitioningIndex(where belongsAfter: (Element) -> Bool) -> Int {
        var low = startIndex
        var high = endIndex
        while low < high {
            let middle = low + (high - low) / 2
            if belongsAfter(self[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}
