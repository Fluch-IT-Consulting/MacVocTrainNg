import Foundation

/// One change to a deck: cards to replace or add, cards to remove and new learning
/// options. `Deck.apply(_:day:)` makes it and returns the change that reverts it.
///
/// Only VocabCore builds changes: outside it, the factory methods below and
/// `SessionMode.grade(_:in:at:)` are the only way. So the app can't set a card's
/// learning state or log on its own.
public struct DeckChange: Sendable {
    /// Cards to replace (matched by ID) or insert at the given index (appended if `nil`).
    /// Only the inverse of removals inserts at an index.
    var upserts: [(card: Card, index: Int?)]
    var removals: [Card.ID]
    /// New learning options; `nil` keeps them.
    var learningOptions: LearningOptions?

    /// - Parameter upserts: Cards that replace the cards with the same ID; cards with a
    ///   new ID are appended.
    init(upserts: [Card] = [], removals: [Card.ID] = [], learningOptions: LearningOptions? = nil) {
        self.upserts = upserts.map { ($0, nil) }
        self.removals = removals
        self.learningOptions = learningOptions
    }
}

extension DeckChange {
    /// Appends `cards` to `deck`. Only new cards without a log whose ID `deck` doesn't
    /// hold yet are added, so adding never replaces a card; `nil` if that leaves none.
    public static func adding(_ cards: [Card], to deck: Deck) -> DeckChange? {
        var ids = Set(deck.cards.map(\.id))
        let added = cards.filter { $0.isNew && $0.log.isEmpty && ids.insert($0.id).inserted }
        return added.isEmpty ? nil : DeckChange(upserts: added)
    }

    /// Removes the cards with `ids` from `deck`; `nil` if `deck` holds none of them.
    public static func removing(_ ids: Set<Card.ID>, from deck: Deck) -> DeckChange? {
        let removals = deck.cards.map(\.id).filter(ids.contains)
        return removals.isEmpty ? nil : DeckChange(removals: removals)
    }

    /// Replaces question, answer and hint of the card with `id` in `deck` by `text`,
    /// keeping its learning state; `nil` if `deck` doesn't hold it or the text stays.
    public static func editingText(of id: Card.ID, to text: CardText, in deck: Deck) -> DeckChange? {
        guard let card = deck.card(withID: id) else { return nil }
        var edited = card
        edited.question = text.question
        edited.answer = text.answer
        edited.hint = text.hint
        return edited == card ? nil : DeckChange(upserts: [edited])
    }

    /// Makes the cards with `ids` in `deck` new again, keeping their content. Cards
    /// that are new already and have no log stay out; `nil` if that leaves none.
    public static func resettingLearningState(of ids: Set<Card.ID>, in deck: Deck) -> DeckChange? {
        let cards = deck.cards.filter { ids.contains($0.id) && (!$0.isNew || !$0.log.isEmpty) }.map { card in
            var card = card
            card.resetLearningState()
            return card
        }
        return cards.isEmpty ? nil : DeckChange(upserts: cards)
    }

    /// Sets the learning options of `deck`, or `nil` if they don't change. New FSRS
    /// parameters also replay stability and difficulty of every card with a complete
    /// review log (`Scheduler.replayingMemory(of:)`); due dates stay.
    public static func changingLearningOptions(_ learningOptions: LearningOptions, in deck: Deck, calendar: StudyCalendar) -> DeckChange? {
        guard deck.learningOptions != learningOptions else { return nil }
        var replayed: [Card] = []
        if learningOptions.parameters != deck.learningOptions.parameters {
            let scheduler = Scheduler(learningOptions: learningOptions, calendar: calendar)
            replayed = deck.cards.compactMap { card in
                guard let replayed = scheduler.replayingMemory(of: card), replayed != card else { return nil }
                return replayed
            }
        }
        return DeckChange(upserts: replayed, learningOptions: learningOptions)
    }
}

extension Deck {
    /// Applies `change` and returns the change that reverts it.
    ///
    /// A change to the cards records their distribution as the snapshot for `day`;
    /// learning options alone move no card between the bins of a snapshot. Applying
    /// the inverse records the snapshot again rather than restoring the old one. That
    /// holds when the inverse comes on a later study day, too, e.g. undoing a review
    /// the next morning: a snapshot shows the cards at the end of its day, and at the
    /// end of the earlier day the change was still in effect. So only the snapshot of
    /// `day` changes, never an earlier one.
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
