import Foundation
import Observation
import Testing
import VocabCore

@testable import MacVocTrain

/// Counts calls of a sendable closure. Only used on the main actor.
private final class ChangeCount: @unchecked Sendable {
    var value = 0
}

@MainActor
struct DueCardCounterTests {
    @Test func dueCardsAreCountedAsTimePasses() {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_791_216_000))
        let learningState = LearningState(phase: .review, stability: 1, difficulty: 5, lastReview: clock.now, due: clock.now.addingTimeInterval(3600))
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        let document = VocabularyDocument(deck: Deck(cards: [card, Card(question: "kot", answer: "Katze")]), clock: clock.studyClock)
        let dueCards = document.dueCards
        #expect(dueCards.count == 1)

        clock.now = card.learningState!.due.addingTimeInterval(60)
        #expect(dueCards.count == 1)
        dueCards.refresh()
        #expect(dueCards.count == 2)
    }

    /// The counter counts again at the start of every minute, like `TimelineView(.everyMinute)`.
    @Test func dueCardsAreCountedOnTheFullMinute() {
        let minute = Date(timeIntervalSince1970: 1_791_216_000)
        let next = minute.addingTimeInterval(60)
        #expect(DueCardCounter.nextRefresh(after: minute) == next)
        #expect(DueCardCounter.nextRefresh(after: minute.addingTimeInterval(0.001)) == next)
        #expect(DueCardCounter.nextRefresh(after: minute.addingTimeInterval(30)) == next)
        #expect(DueCardCounter.nextRefresh(after: next.addingTimeInterval(-0.001)) == next)
    }

    @Test func dueCardsAreCountedAfterEveryChange() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager(for: document)
        #expect(document.dueCards.count == 0)

        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!) }
        #expect(document.dueCards.count == 1)
        undoManager.undo()
        #expect(document.dueCards.count == 0)
    }

    @Test func dueCardsTellObserversOnlyWhenTheNumberChanges() {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_791_216_000))
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus")]), clock: clock.studyClock)
        let undoManager = makeUndoManager(for: document)
        let dueCards = document.dueCards
        let changes = ChangeCount()
        withObservationTracking {
            _ = dueCards.count
        } onChange: {
            changes.value += 1
        }

        clock.now.addTimeInterval(60)
        dueCards.refresh()
        #expect(changes.value == 0)

        step(undoManager) { document.add(CardText(question: "kot", answer: "Katze")!) }
        #expect(changes.value == 1)
    }
}
