import Foundation
@testable import VocabCore

extension Deck {
    /// Applies `change` at the start of `day` in the testing calendar, for tests that
    /// don't care about the time of a change.
    mutating func apply(_ change: DeckChange, day: Int) -> DeckChange {
        apply(change, at: StudyCalendar.testing.start(ofDay: day), calendar: .testing)
    }

    /// Appends `cards` without the checks of building a deck from its parts, for tests
    /// that need an invalid deck, such as one with duplicate card IDs.
    mutating func appendUnchecked(_ cards: [Card]) {
        self.cards += cards
    }
}
