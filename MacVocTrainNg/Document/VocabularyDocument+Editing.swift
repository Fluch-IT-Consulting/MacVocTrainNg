import Foundation
import VocabCore

/// The changes of a deck that only the Mac app makes: the iPhone app only studies and
/// never edits cards (#254, #289), and doesn't compile these (#297). Each goes through
/// `perform(_:actionName:alongside:)`, which registers its undo action.
extension VocabularyDocument {
    /// Appends a new card with `text`, created now by the document's clock, see
    /// `DeckChange.adding(_:to:)`. Returns the ID of the new card.
    @discardableResult
    func add(_ text: CardText) -> Card.ID {
        let card = Card(text: text, created: clock.now)
        if let change = DeckChange.adding([card], to: deck) {
            perform(change, actionName: String(localized: "Add Card"))
        }
        return card.id
    }

    /// Appends cards from an import as one change, see `DeckChange.adding(_:to:)`.
    func importCards(_ cards: [Card]) {
        guard let change = DeckChange.adding(cards, to: deck) else { return }
        perform(change, actionName: String(localized: "Import Cards"))
    }

    /// Changes question, answer and hint of a card, see `DeckChange.editingText(of:to:in:)`.
    func editText(of id: Card.ID, to text: CardText) {
        guard let change = DeckChange.editingText(of: id, to: text, in: deck) else { return }
        perform(change, actionName: String(localized: "Edit Card"))
    }

    func delete(_ ids: Set<Card.ID>) {
        guard let change = DeckChange.removing(ids, from: deck) else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(change, actionName: name)
    }

    func resetLearningState(of ids: Set<Card.ID>) {
        guard let change = DeckChange.resettingLearningState(of: ids, in: deck, at: clock.now) else { return }
        perform(change, actionName: String(localized: "Reset Learning State"))
    }

    /// Changes the learning options, see `DeckChange.changingLearningOptions(_:in:calendar:)`.
    func updateLearningOptions(_ learningOptions: LearningOptions) {
        guard let change = DeckChange.changingLearningOptions(learningOptions, in: deck, calendar: calendar) else { return }
        perform(change, actionName: String(localized: "Change Learning Options"))
    }
}
