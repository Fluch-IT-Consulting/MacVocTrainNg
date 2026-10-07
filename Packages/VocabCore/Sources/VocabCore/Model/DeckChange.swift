import Foundation

/// One change to a deck: cards to replace or add, cards to remove and new learning
/// options. `Deck.apply(_:day:)` makes it and returns the change that reverts it.
public struct DeckChange: Sendable {
    /// Cards to replace (matched by ID) or insert at the given index (appended if `nil`).
    /// Only the inverse of removals inserts at an index.
    var upserts: [(card: Card, index: Int?)]
    var removals: [Card.ID]
    /// New learning options; `nil` keeps them.
    var learningOptions: LearningOptions?

    /// - Parameter upserts: Cards that replace the cards with the same ID; cards with a
    ///   new ID are appended.
    public init(upserts: [Card] = [], removals: [Card.ID] = [], learningOptions: LearningOptions? = nil) {
        self.upserts = upserts.map { ($0, nil) }
        self.removals = removals
        self.learningOptions = learningOptions
    }
}

extension Deck {
    /// Applies `change` and returns the change that reverts it.
    ///
    /// A change to the cards records their distribution as the snapshot for `day`;
    /// learning options alone move no card between the bins of a snapshot. Applying
    /// the inverse records the snapshot again rather than restoring the old one.
    public mutating func apply(_ change: DeckChange, day: Int) -> DeckChange {
        var inverse = DeckChange()

        if let learningOptions = change.learningOptions {
            inverse.learningOptions = self.learningOptions
            self.learningOptions = learningOptions
        }

        // Every step below passes over the cards once: a change may touch all of them.
        if !change.removals.isEmpty {
            let removals = Set(change.removals)
            // In ascending order, so the inverse re-inserts each card at its old index.
            inverse.upserts = cards.enumerated().filter { removals.contains($0.element.id) }.map { ($0.element, $0.offset) }
            cards.removeAll { removals.contains($0.id) }
        }

        var indices = Dictionary(cards.enumerated().map { ($0.element.id, $0.offset) }) { first, _ in first }
        var insertions: [(card: Card, index: Int)] = []
        for (card, position) in change.upserts {
            if let index = indices[card.id] {
                inverse.upserts.append((cards[index], nil))
                cards[index] = card
            } else if let position {
                insertions.append((card, position))
                inverse.removals.append(card.id)
            } else {
                indices[card.id] = cards.count
                cards.append(card)
                inverse.removals.append(card.id)
            }
        }
        if !insertions.isEmpty {
            cards = Self.inserting(insertions, into: cards)
        }

        if !change.upserts.isEmpty || !change.removals.isEmpty {
            updateProgress(day: day)
        }
        return inverse
    }

    /// Inserts cards at their indices in one pass. Only the inverse of removals inserts
    /// at an index, in ascending order; each card lands where inserting the cards one
    /// after another would put it.
    private static func inserting(_ insertions: [(card: Card, index: Int)], into cards: [Card]) -> [Card] {
        assert(zip(insertions, insertions.dropFirst()).allSatisfy { $0.index < $1.index })
        var result: [Card] = []
        result.reserveCapacity(cards.count + insertions.count)
        var remaining = cards[...]
        for (card, index) in insertions {
            let count = min(index - result.count, remaining.count)
            result.append(contentsOf: remaining.prefix(count))
            remaining = remaining.dropFirst(count)
            result.append(card)
        }
        result.append(contentsOf: remaining)
        return result
    }
}
