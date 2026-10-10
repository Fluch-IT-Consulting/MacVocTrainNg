import Foundation
@testable import VocabCore

extension Deck {
    /// Applies `change` at the start of `day` in the testing calendar, for tests that
    /// don't care about the time of a change.
    mutating func apply(_ change: DeckChange, day: Int) -> DeckChange {
        apply(change, at: StudyCalendar.testing.start(ofDay: day), calendar: .testing)
    }
}
