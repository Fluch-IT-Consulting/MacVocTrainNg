import Combine
import Foundation
import Testing
import VocabCore

@testable import MacVocTrain

@MainActor
struct DocumentTests {
    @Test func addingIsUndoable() throws {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager(for: document)

        var id: Card.ID?
        step(undoManager) { id = document.add(CardText(question: " dom", answer: "Haus ", hint: "Gebäude")!) }
        let card = try #require(document.deck.cards.first)
        #expect(document.deck.cards == [card])
        #expect(card.id == id)
        #expect([card.question, card.answer, card.hint] == ["dom", "Haus", "Gebäude"])
        #expect(card.isNew)
        #expect(undoManager.undoActionName == "Add Card" || undoManager.undoActionName == "Karte hinzufügen")

        undoManager.undo()
        #expect(document.deck.cards.isEmpty)
        undoManager.redo()
        #expect(document.deck.cards == [card])
    }

    @Test func addedCardsAreCreatedByTheDocumentsClock() {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))
        let document = VocabularyDocument(clock: clock.studyClock)
        let undoManager = makeUndoManager(for: document)

        var first: Card.ID?
        step(undoManager) { first = document.add(CardText(question: "dom", answer: "Haus")!) }
        #expect(first.flatMap(document.card(withID:))?.created == clock.now)

        clock.now.addTimeInterval(3600)
        var second: Card.ID?
        step(undoManager) { second = document.add(CardText(question: "kot", answer: "Katze")!) }
        #expect(second.flatMap(document.card(withID:))?.created == clock.now)
    }

    /// No caller hands over an undo manager: every change registers its undo action with
    /// the document's (#195).
    @Test func everyChangeRegistersWithTheDocumentsUndoManager() {
        let learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: Date(), due: Date())
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager(for: document)
        var options = LearningOptions()
        options.caseSensitive.toggle()
        let changes: [() -> Void] = [
            { _ = document.add(CardText(question: "kot", answer: "Katze")!) },
            { document.importCards([Card(question: "pies", answer: "Hund")]) },
            { document.editText(of: card.id, to: CardText(question: "dom", answer: "Heim")!) },
            { document.resetLearningState(of: [card.id]) },
            { document.updateLearningOptions(options) },
            { document.delete([card.id]) },
        ]

        for change in changes {
            step(undoManager, change)
        }
        for _ in changes {
            #expect(undoManager.canUndo)
            undoManager.undo()
        }
        #expect(!undoManager.canUndo)
        #expect(document.deck.cards == [card])
        #expect(document.deck.learningOptions == LearningOptions())
    }

    @Test func importIsOneUndoableChange() {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus")]))
        let undoManager = makeUndoManager(for: document)
        let imported = [Card(question: "kot", answer: "Katze"), Card(question: "pies", answer: "Hund")]

        step(undoManager) { document.importCards(imported) }
        #expect(document.deck.cards.map(\.question) == ["dom", "kot", "pies"])
        #expect(undoManager.undoActionName == "Import Cards" || undoManager.undoActionName == "Karten importieren")

        undoManager.undo()
        #expect(document.deck.cards.map(\.question) == ["dom"])
    }

    @Test func editingAndResettingAreUndoable() {
        let learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: Date(), due: Date())
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager(for: document)

        let edited = card.withAnswer("Haus / Heim")
        step(undoManager) { document.editText(of: card.id, to: CardText(question: "dom", answer: "Haus / Heim")!) }
        #expect(document.deck.cards[0] == edited)
        step(undoManager) { document.resetLearningState(of: [card.id]) }
        #expect(document.deck.cards[0].isNew)
        #expect(document.deck.cards[0].answer == "Haus / Heim")

        undoManager.undo()
        #expect(document.deck.cards[0] == edited)
        undoManager.undo()
        #expect(document.deck.cards[0] == card)
    }

    @Test func unchangedEditRegistersNoUndo() {
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager(for: document)
        document.editText(of: card.id, to: CardText(question: " dom", answer: "Haus")!)  // would throw without an open group if it registered anything
        #expect(!undoManager.canUndo)
    }

    @Test func changesAreAnnouncedBeforeAndReportedAfter() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager(for: document)
        var events: [String] = []
        let willChange = document.objectWillChange.sink { events.append("will \(document.deck.cards.count)") }
        let didChange = document.deckDidChange.sink { events.append("did \(document.deck.cards.count)") }

        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!) }
        undoManager.undo()
        #expect(events == ["will 0", "did 1", "will 1", "did 0"])
        _ = (willChange, didChange)
    }

    @Test func theCalendarIsTheOneGiven() {
        #expect(VocabularyDocument(calendar: .testing).calendar == .testing)
        #expect(VocabularyDocument().calendar == StudyCalendar())
    }

    @Test func changesUpdateTodaysSnapshot() {
        let document = VocabularyDocument(calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!) }
        #expect(document.deck.progress.last?.day == document.calendar.dayNumber(for: Date()))
        #expect(document.deck.progress.last?.total == 1)
    }

    /// The calendar follows the machine's time zone; the study day still starts at the
    /// same hour (#186).
    @Test func theCalendarSwitchesToANewTimeZone() {
        let document = VocabularyDocument(calendar: .testing)
        var changes = 0
        let willChange = document.objectWillChange.sink { changes += 1 }

        document.switchTimeZone(to: StudyCalendar.newYork.timeZone)
        #expect(document.calendar == .newYork)
        #expect(changes == 1)
        document.switchTimeZone(to: StudyCalendar.newYork.timeZone)
        #expect(changes == 1)
        _ = willChange
    }

    /// After the machine's time zone changed, a change to the open deck updates the
    /// snapshot of the study day in the new zone (#186).
    @Test func changesAfterATimeZoneSwitchUpdateTheNewStudyDay() {
        let day = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        // 23:00 in New York, already 05:00 of the next day in Berlin.
        let clock = ManualClock(StudyCalendar.newYork.start(ofDay: day).addingTimeInterval(19 * 3600))
        let document = VocabularyDocument(clock: clock.studyClock, calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        #expect(document.calendar.dayNumber(for: clock.now) == day + 1)

        document.switchTimeZone(to: StudyCalendar.newYork.timeZone)
        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!) }
        #expect(document.deck.progress.map(\.day) == [day])
    }

    @Test func snapshotSavesReadableDeck() throws {
        // The file stores dates with second precision.
        let created = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let document = VocabularyDocument(deck: Deck(cards: [Card(text: CardText(question: "dom", answer: "Haus")!, created: created)]))
        let snapshot = try document.snapshot(contentType: .vocabularyDeck)
        #expect(try DeckFile.decode(DeckFile.fileWrapper(for: snapshot)) == document.deck)
    }

    @Test func everyDeckFileErrorOpensWithItsOwnMessage() {
        let errors: [DeckFile.Error] = [
            .notADeck, .unsupportedVersion(4), .outdatedVersion(2), .damagedReviewLog(line: 3), .missingReviewLog,
            .reviewsOfUnknownCard(line: 3), .reviewLogTooLong(question: "dom"), .duplicateCardID(question: "dom"),
            .parameterOutOfRange(index: 20),
        ]
        let openingErrors = errors.map(VocabularyDocument.openingError(for:))
        #expect(openingErrors.allSatisfy { $0 is AppError })
        #expect(Set(openingErrors.map(\.localizedDescription)).count == errors.count)
    }

    @Test func otherErrorsOpenWithTheirCauseAttached() throws {
        enum Cause: Error { case test }
        let error = try #require(VocabularyDocument.openingError(for: Cause.test) as? CocoaError)
        #expect(error.code == .fileReadCorruptFile)
        #expect(error.userInfo[NSUnderlyingErrorKey] as? Cause == .test)
    }

    /// The first save of a new deck takes the snapshot on a background thread.
    @Test func snapshotOffTheMainThreadHoldsTheLatestChange() async throws {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager(for: document)
        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!) }
        let snapshot = try await Task.detached { try document.snapshot(contentType: .vocabularyDeck) }.value
        #expect(snapshot == document.deck)
    }

    @Test func newParametersReplayMemoryInOneUndoableChange() throws {
        let scheduler = Scheduler(learningOptions: LearningOptions(), calendar: .testing)
        let start = Date(timeIntervalSince1970: 1_791_216_000)
        var random = SeededRandom(seed: 1)
        let studied = [(0.0, Grade.good), (60.0, .good), (20.0 * 86400, .good)].reduce(Card(question: "dom", answer: "Haus")) {
            scheduler.review($0, grade: $1.1, at: start.addingTimeInterval($1.0), using: &random)
        }
        let document = VocabularyDocument(deck: Deck(cards: [studied]))
        let undoManager = makeUndoManager(for: document)

        var options = LearningOptions()
        var weights = FSRSParameters.default.weights
        weights[8] = 1.2
        options.parameters = try #require(FSRSParameters(weights))
        step(undoManager) { document.updateLearningOptions(options) }
        let replayed = document.deck.cards
        #expect(replayed != [studied])
        #expect(undoManager.undoActionName == "Change Learning Options" || undoManager.undoActionName == "Lernoptionen ändern")

        undoManager.undo()
        #expect(document.deck.learningOptions == LearningOptions())
        #expect(document.deck.cards == [studied])
        undoManager.redo()
        #expect(document.deck.learningOptions == options)
        #expect(document.deck.cards == replayed)
    }

    @Test func unchangedLearningOptionsRegisterNoUndo() {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus")]))
        let undoManager = makeUndoManager(for: document)
        document.updateLearningOptions(LearningOptions())  // would throw without an open group if it registered anything
        #expect(!undoManager.canUndo)
    }

    /// Undo and redo of a review run its companion once the deck holds the card as it
    /// was before or after the review (#164).
    @Test func reviewUndoRunsItsCompanionAfterTheCard() {
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(cards: [card]), calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        var mode = SessionMode.study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar))
        guard case let .rescheduled(change) = mode.grade(.good, in: document.deck, at: document.clock.now, calendar: document.calendar) else {
            Issue.record("A study session reschedules the card.")
            return
        }
        let calls = CompanionCalls()
        let companion = UndoCompanion(
            undo: { calls.entries.append("undo \(document.card(withID: card.id)?.log.count ?? -1)") },
            redo: { calls.entries.append("redo \(document.card(withID: card.id)?.log.count ?? -1)") }
        )
        step(undoManager) { document.applyReview(change, alongside: companion) }
        #expect(calls.entries.isEmpty)

        undoManager.undo()
        #expect(!undoManager.canUndo)
        undoManager.redo()
        undoManager.undo()
        #expect(calls.entries == ["undo 0", "redo 1", "undo 0"])
    }

    /// The undo actions don't hold their undo manager, which outlives a closed deck
    /// otherwise (#181).
    @Test func undoActionsLetTheirUndoManagerGo() {
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(cards: [card]), calendar: .testing)
        var mode = SessionMode.study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar))
        guard case let .rescheduled(change) = mode.grade(.good, in: document.deck, at: document.clock.now, calendar: document.calendar) else {
            Issue.record("A study session reschedules the card.")
            return
        }
        let calls = CompanionCalls()
        let companion = UndoCompanion(undo: { calls.entries.append("undo") }, redo: { calls.entries.append("redo") })
        weak var released: UndoManager?
        autoreleasepool {
            let undoManager = makeUndoManager(for: document)
            step(undoManager) { document.applyReview(change, alongside: companion) }
            step(undoManager) { document.add(CardText(question: "kot", answer: "Katze")!) }
            undoManager.undo()
            #expect(undoManager.canUndo && undoManager.canRedo)
            released = undoManager
        }
        #expect(released == nil)
    }
}

/// The calls of an `UndoCompanion` in a test.
@MainActor
private final class CompanionCalls {
    var entries: [String] = []
}
