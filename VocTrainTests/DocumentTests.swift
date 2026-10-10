import Foundation
import Testing
import VocabCore

@testable import VocTrain

/// The document the iPhone app shares with the Mac app, on iOS.
@MainActor
struct DocumentTests {
    @Test func reviewIsUndoable() throws {
        let created = Date(timeIntervalSince1970: 1_791_216_000)
        let card = Card(text: CardText(question: "dom", answer: "Haus")!, created: created)
        let document = VocabularyDocument(deck: Deck(cards: [card]), clock: StudyClock { created.addingTimeInterval(60) })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        document.undoManager = undoManager
        var mode = SessionMode.study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar))

        let outcome = mode.grade(.good, in: document.deck, at: document.clock.now, calendar: document.calendar)
        guard case let .rescheduled(change) = outcome else {
            Issue.record("The study session didn't reschedule the card.")
            return
        }
        undoManager.beginUndoGrouping()
        document.applyReview(change, alongside: UndoCompanion(undo: {}, redo: {}))
        undoManager.endUndoGrouping()
        #expect(document.deck.cards.first?.log.map(\.grade) == [.good])

        undoManager.undo()
        #expect(document.deck.cards == [card])
    }

    @Test func dueCardsCountNewCards() {
        let created = Date(timeIntervalSince1970: 1_791_216_000)
        let cards = ["dom", "kot"].map { Card(text: CardText(question: $0, answer: "x")!, created: created) }
        let document = VocabularyDocument(deck: Deck(cards: cards), clock: StudyClock { created })
        #expect(document.dueCards.count == 2)
    }
}
