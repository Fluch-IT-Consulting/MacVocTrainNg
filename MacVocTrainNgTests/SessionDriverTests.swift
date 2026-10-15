import Foundation
import Testing

@testable import MacVocTrain
@testable import VocabCore

/// The part of a session that Mac and iPhone share: grades, undo and redo, and cards
/// deleted while the session runs (#264).
@MainActor
struct SessionDriverTests {
    /// A study session over new cards, with a listener as its delegate. The test keeps
    /// the undo manager and the listener, which the document and the driver hold weakly.
    private func makeDriver(cards: Int) throws -> (SessionDriver, UndoManager, DriverListener) {
        var learningOptions = LearningOptions()
        learningOptions.steps = 1
        learningOptions.fuzzing = false
        let document = try VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: (0..<cards).map { Card(question: "q\($0)", answer: "a\($0)") }), calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        let driver = SessionDriver(document: document, mode: .study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar)))
        let listener = DriverListener()
        driver.delegate = listener
        return (driver, undoManager, listener)
    }

    @Test func undoAndRedoBringBackTheCardAndThePlace() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 2)
        let document = driver.document
        let first = try #require(driver.currentCard)

        var recorded = false
        step(undoManager) { recorded = driver.grade(.good) }
        #expect(recorded)
        #expect(document.card(withID: first.id)?.log.map(\.grade) == [.good])
        #expect(driver.currentCard?.id != first.id)
        #expect(driver.session.reviewCount == 1)
        #expect(listener.moves == 1)

        undoManager.undo()
        #expect(document.card(withID: first.id) == first)
        #expect(driver.currentCard == first)
        #expect(driver.session.reviewCount == 0)
        #expect(listener.restores == 1)
        #expect(listener.moves == 2)
        #expect(!undoManager.canUndo)  // card and place in one step

        undoManager.redo()
        #expect(document.card(withID: first.id)?.log.map(\.grade) == [.good])
        #expect(driver.currentCard?.id != first.id)
        #expect(driver.session.reviewCount == 1)
        #expect(listener.restores == 2)
    }

    @Test func undoOfAPracticeReviewBringsBackThePlace() throws {
        let (driver, undoManager, _) = try makeDriver(cards: 1)
        let card = try #require(driver.currentCard)
        driver.start(.practice(Practice(practicing: [card.id], at: driver.document.clock.now)))
        let deck = driver.document.deck

        step(undoManager) { driver.grade(.good) }
        #expect(driver.session.reviewCount == 1)
        #expect(driver.document.deck == deck)
        #expect(undoManager.undoActionName == String(localized: "Review"))

        undoManager.undo()
        #expect(driver.session.reviewCount == 0)
        #expect(driver.currentCard == card)

        undoManager.redo()
        #expect(driver.session.reviewCount == 1)
    }

    @Test func undoingAReviewOfAnEarlierSessionOnlyTakesBackTheCard() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 2)
        let first = try #require(driver.currentCard)
        step(undoManager) { driver.grade(.good) }
        driver.start(.study(StudySession(deck: driver.document.deck, at: driver.document.clock.now, calendar: driver.document.calendar)))
        let session = driver.session.id
        let current = driver.currentCard

        undoManager.undo()
        #expect(driver.document.card(withID: first.id) == first)
        #expect(driver.session.id == session)
        #expect(driver.currentCard == current)
        #expect(listener.restores == 0)
    }

    /// Finishing up has no undo of its own (#180).
    @Test func finishingUpOutlastsUndoAndRedo() throws {
        let (driver, undoManager, _) = try makeDriver(cards: 3)
        let first = try #require(driver.currentCard)
        step(undoManager) { driver.grade(.again) }
        driver.finishUp()
        #expect(driver.session.totalCount == 2)
        let finishedUp = driver.currentCard

        undoManager.undo()
        #expect(driver.currentCard?.id == first.id)
        #expect(driver.session.totalCount == 1)  // the card asked after the review is out

        undoManager.redo()
        #expect(driver.session.totalCount == 2)
        #expect(driver.currentCard == finishedUp)
    }

    /// Suspending is undone like a review: the card and the place in one step (#290).
    @Test func suspendingTheCardBeingAskedMovesOnUntilUndone() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 2)
        let document = driver.document
        let first = try #require(driver.currentCard)

        var suspended = false
        step(undoManager) { suspended = driver.suspendCurrentCard() }
        #expect(suspended)
        #expect(document.card(withID: first.id)?.isSuspended == true)
        #expect(driver.currentCard != nil)
        #expect(driver.currentCard?.id != first.id)
        #expect(driver.session.totalCount == 1)
        #expect(driver.session.suspendedCount == 1)
        #expect(driver.session.reviewCount == 0)
        #expect(listener.moves == 1)
        #expect(undoManager.undoActionName == String(localized: "Suspend Card"))

        undoManager.undo()
        #expect(document.card(withID: first.id) == first)
        #expect(driver.currentCard == first)
        #expect(driver.session.totalCount == 2)
        #expect(driver.session.suspendedCount == 0)
        #expect(!undoManager.canUndo)

        undoManager.redo()
        #expect(document.card(withID: first.id)?.isSuspended == true)
        #expect(driver.currentCard?.id != first.id)
        #expect(driver.session.suspendedCount == 1)
    }

    @Test func suspendingTheLastCardFinishesTheSession() throws {
        let (driver, undoManager, _) = try makeDriver(cards: 1)
        step(undoManager) { driver.suspendCurrentCard() }
        #expect(driver.session.isFinished)
        #expect(driver.currentCard == nil)
        #expect(!driver.suspendCurrentCard())
    }

    /// E.g. after a merge with a version from the iPhone that suspended it.
    @Test func aCardSuspendedMeanwhileIsSkipped() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 3)
        let current = try #require(driver.currentCard)
        let other = try #require(driver.document.deck.cards.first { $0.id != current.id })

        step(undoManager) { driver.document.setSuspended(true, of: [current.id, other.id]) }
        let remaining = try #require(driver.currentCard)
        #expect(remaining.id != current.id && remaining.id != other.id)
        #expect(listener.moves == 1)
        // Only the learner's own suspensions count.
        #expect(driver.session.suspendedCount == 0)

        step(undoManager) { driver.grade(.good) }
        #expect(driver.session.isFinished)
    }

    /// E.g. after undoing "Add Card", or after a merge with a version that deleted it.
    @Test func aDeletedCardBeingAskedIsSkipped() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 2)
        let current = try #require(driver.currentCard)

        step(undoManager) { driver.document.delete([current.id]) }
        #expect(driver.currentCard != nil)
        #expect(driver.currentCard?.id != current.id)
        #expect(driver.session.totalCount == 1)
        #expect(listener.moves == 1)
    }

    @Test func aDeletedCardLaterInTheSessionIsSkipped() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 2)
        let current = try #require(driver.currentCard)
        let other = try #require(driver.document.deck.cards.first { $0.id != current.id })

        step(undoManager) { driver.document.delete([other.id]) }
        #expect(driver.currentCard == current)
        #expect(listener.changes == 1)
        #expect(listener.moves == 0)

        step(undoManager) { driver.grade(.good) }
        #expect(driver.currentCard == nil)
        #expect(driver.session.isFinished)
    }

    @Test func anEditOfTheCardBeingAskedShowsUp() throws {
        let (driver, undoManager, listener) = try makeDriver(cards: 1)
        let card = try #require(driver.currentCard)

        step(undoManager) { driver.document.editText(of: card.id, to: CardText(question: card.question, answer: "Heim")!) }
        #expect(driver.currentCard?.answer == "Heim")
        #expect(listener.changes == 1)
        #expect(listener.moves == 0)
    }
}

/// Counts what a `SessionDriver` tells its delegate.
@MainActor
private final class DriverListener: SessionDriverDelegate {
    var moves = 0
    var changes = 0
    var restores = 0

    func sessionDriverDidMoveOn(_ driver: SessionDriver) {
        moves += 1
    }

    func sessionDriverCardDidChange(_ driver: SessionDriver) {
        changes += 1
    }

    func sessionDriverDidRestore(_ driver: SessionDriver) {
        restores += 1
    }
}
