import Combine
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
        guard case let .rescheduled(change) = mode.grade(.good, in: document.deck, at: document.clock.now) else {
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
        guard case let .rescheduled(change) = mode.grade(.good, in: document.deck, at: document.clock.now) else {
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

@MainActor
struct SessionViewModelTests {
    private func makeDocument(cards: Int, steps: Int = 1) -> VocabularyDocument {
        var learningOptions = LearningOptions()
        learningOptions.steps = steps
        learningOptions.fuzzing = false
        return VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: (0..<cards).map { Card(question: "q\($0)", answer: "a\($0)") }), calendar: .testing)
    }

    @Test func correctResponseMovesOnAndCanBeUndone() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)

        model.input = first.answer
        step(undoManager) { model.submit() }
        #expect(document.card(withID: first.id)?.learningState?.phase == .review)
        #expect(model.previous?.grade == .good)
        #expect(model.currentCard?.id != first.id)
        #expect(model.session.completedCount == 1)

        #expect(undoManager.undoActionName == String(localized: "Review"))

        undoManager.undo()
        #expect(document.card(withID: first.id)?.isNew == true)
        #expect(model.currentCard == first)
        #expect(model.session.completedCount == 0)
        #expect(model.stage == .asking)
        #expect(!undoManager.canUndo)  // card and session in one step
        #expect(undoManager.redoActionName == String(localized: "Review"))

        undoManager.redo()
        #expect(document.card(withID: first.id)?.learningState?.phase == .review)
        #expect(model.currentCard?.id != first.id)
        #expect(model.session.completedCount == 1)
        #expect(undoManager.undoActionName == String(localized: "Review"))
    }

    @Test func undoingAReviewOfAnEarlierSessionOnlyTakesBackTheCard() throws {
        let document = makeDocument(cards: 2, steps: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)
        model.input = first.answer
        step(undoManager) { model.submit() }

        model.continueStudying()
        let session = model.session.id
        let current = try #require(model.currentCard)

        undoManager.undo()
        #expect(document.card(withID: first.id)?.isNew == true)
        #expect(model.session.id == session)
        #expect(model.currentCard?.id == current.id)

        undoManager.redo()
        #expect(document.card(withID: first.id)?.log.count == 1)
        #expect(model.session.id == session)
    }

    /// What undo and redo of a review must bring back. The cards rather than the deck:
    /// undo records today's snapshot again instead of restoring the old one.
    private struct Place: Equatable {
        var cards: [Card]
        var currentCardID: Card.ID?
        var completedCount: Int
        var totalCount: Int
        var reviewCount: Int
        var stage: SessionViewModel.Stage

        @MainActor init(_ model: SessionViewModel) {
            cards = model.document.deck.cards
            currentCardID = model.currentCard?.id
            completedCount = model.session.completedCount
            totalCount = model.session.totalCount
            reviewCount = model.session.reviewCount
            stage = model.stage
        }
    }

    /// Each undo and redo registers the opposite step anew; the stack must stay in order.
    @Test func severalReviewsAreUndoneAndRedoneOneByOne() throws {
        let document = makeDocument(cards: 3)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        var places = [Place(model)]
        for _ in 0..<3 {
            model.input = try #require(model.currentCard).answer
            step(undoManager) { model.submit() }
            places.append(Place(model))
        }
        #expect(model.isFinished)

        for place in places.dropLast().reversed() {
            undoManager.undo()
            #expect(Place(model) == place)
        }
        #expect(!undoManager.canUndo)

        for place in places.dropFirst() {
            undoManager.redo()
            #expect(Place(model) == place)
        }
        #expect(!undoManager.canRedo)
    }

    @Test func undoingTheReviewThatFinishedTheSessionAsksAgain() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let card = try #require(model.currentCard)
        model.input = card.answer
        step(undoManager) { model.submit() }
        #expect(model.isFinished)

        undoManager.undo()
        #expect(model.stage == .asking)
        #expect(model.currentCard == card)

        undoManager.redo()
        #expect(model.isFinished)
    }

    /// The summary shows the time up to the last review, however long it stays open (#185).
    @Test func durationStaysTheSameAfterTheSessionEnds() throws {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_791_216_000))
        var learningOptions = LearningOptions()
        learningOptions.steps = 1
        let deck = Deck(learningOptions: learningOptions, cards: [Card(question: "dom", answer: "Haus")])
        let document = VocabularyDocument(deck: deck, clock: clock.studyClock, calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)

        clock.now.addTimeInterval(30)
        model.input = "Haus"
        step(undoManager) { model.submit() }
        #expect(model.isFinished)
        #expect(model.session.duration == 30)

        clock.now.addTimeInterval(5 * 3600)
        undoManager.undo()
        #expect(model.stage == .asking)
        undoManager.redo()
        #expect(model.isFinished)
        #expect(model.session.duration == 30)
    }

    /// The fuzz of intervals belongs to the session's value: after undo, the same grade
    /// gives the same due date.
    @Test func undoingAReviewInLearningRestoresStepAndFuzz() throws {
        let now = Date(timeIntervalSince1970: 1_791_216_000)
        var learningOptions = LearningOptions()
        learningOptions.steps = 2
        learningOptions.fuzzing = true
        // A long stability, so the fuzz has many days to choose from.
        let learningState = LearningState(phase: .learning, stability: 100, difficulty: 5, lastReview: now.addingTimeInterval(-100 * 86400), due: now)
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [card]), clock: ManualClock(now).studyClock, calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "Haus"
        step(undoManager) { model.submit() }
        #expect(document.card(withID: card.id)?.learningState?.step == 1)
        #expect(model.currentCard?.id == card.id)  // stays in the session

        model.input = "Haus"
        step(undoManager) { model.submit() }
        let reviewed = try #require(document.card(withID: card.id)?.learningState)
        #expect(reviewed.phase == .review)
        #expect(model.isFinished)

        undoManager.undo()
        undoManager.undo()
        #expect(document.card(withID: card.id) == card)
        undoManager.redo()
        #expect(document.card(withID: card.id)?.learningState?.step == 1)
        #expect(model.currentCard?.learningState?.step == 1)

        model.input = "Haus"
        step(undoManager) { model.submit() }
        #expect(document.card(withID: card.id)?.learningState == reviewed)
    }

    /// Grades the current card `.again`, so the next card is asked, then finishes up.
    /// Undo and redo of that review must bring back none of the cards not asked by
    /// then (#180).
    private func expectFinishUpOutlastsUndoAndRedo(of model: SessionViewModel, undoManager: UndoManager) throws {
        let first = try #require(model.currentCard)
        model.input = "wrong"
        model.submit()
        step(undoManager) { model.grade(.again) }
        model.finishUp()
        #expect(model.session.totalCount == 2)
        let finishedUp = Place(model)

        undoManager.undo()
        #expect(model.currentCard?.id == first.id)
        #expect(model.session.totalCount == 1)  // the card asked after the review is out
        #expect(model.session.completedCount == 0)

        undoManager.redo()
        #expect(Place(model) == finishedUp)
    }

    @Test func undoingAReviewKeepsTheStudySessionFinishedUp() throws {
        let document = makeDocument(cards: 3)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        try expectFinishUpOutlastsUndoAndRedo(of: model, undoManager: undoManager)
    }

    @Test func undoingAReviewKeepsPracticeFinishedUp() throws {
        let document = makeDocument(cards: 3)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        for _ in 0..<20 where model.session.mistakeIDs.count < 3 {
            model.input = "wrong"
            model.submit()
            step(undoManager) { model.grade(.again) }
        }
        #expect(model.session.mistakeIDs.count == 3)
        model.practiceMistakes()
        #expect(model.isPracticing)
        try expectFinishUpOutlastsUndoAndRedo(of: model, undoManager: undoManager)
    }

    @Test func aNewReviewAfterUndoDropsTheRedo() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)
        model.input = first.answer
        step(undoManager) { model.submit() }

        undoManager.undo()
        #expect(model.currentCard == first)
        model.input = "wrong"
        model.submit()
        step(undoManager) { model.grade(.again) }
        #expect(!undoManager.canRedo)
        #expect(document.card(withID: first.id)?.log.map(\.grade) == [.again])
        #expect(model.session.mistakeIDs == [first.id])

        undoManager.undo()
        #expect(document.card(withID: first.id)?.isNew == true)
        #expect(model.currentCard == first)
        #expect(model.session.mistakeIDs.isEmpty)
        #expect(!undoManager.canUndo)
    }

    @Test func wrongResponseAsksForGrade() throws {
        let document = makeDocument(cards: 2, steps: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let card = try #require(model.currentCard)

        model.input = "nonsense"
        model.submit()
        #expect(model.stage == .feedback(.wrong, response: "nonsense"))
        #expect(model.suggestedGrade == .again)
        #expect(document.card(withID: card.id)?.isNew == true)  // nothing applied yet

        step(undoManager) { model.grade(.again) }
        #expect(document.card(withID: card.id)?.learningState?.phase == .learning)
        #expect(model.session.mistakeIDs == [card.id])
        #expect(model.stage == .asking)
    }

    @Test func typoCanBeAcceptedAsCorrect() throws {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "Tag", answer: "dzień")]))
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "dzien"
        model.submit()
        #expect(model.stage == .feedback(.almostCorrect, response: "dzien"))
        step(undoManager) { model.grade(.good) }
        #expect(document.deck.cards[0].log.map(\.grade) == [.good])
    }

    @Test(arguments: [false, true])
    func highlightingFollowsTheCaseSensitivityOfTheDeck(caseSensitive: Bool) {
        var learningOptions = LearningOptions()
        learningOptions.caseSensitive = caseSensitive
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [Card(question: "Ding", answer: "Wumbel")]))
        let model = SessionViewModel(document: document, autoAdvance: true)
        #expect(model.highlightedAnswer == nil)

        model.input = "wumbl"
        model.submit()
        #expect(model.stage == .feedback(.almostCorrect, response: "wumbl"))
        let marked = model.highlightedAnswer?.filter(\.isMismatch).map(\.text)
        #expect(marked == (caseSensitive ? ["W", "e"] : ["e"]))
    }

    @Test func withoutAutoAdvanceCorrectResponsesAreConfirmed() {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: false)
        model.input = "a0"
        model.submit()
        #expect(model.suggestedGrade == .good)
        step(undoManager) { model.grade(.easy) }
        #expect(document.deck.cards[0].log.map(\.grade) == [.easy])
        #expect(model.isFinished)
    }

    @Test func practicingMistakesLeavesScheduleAlone() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        model.submit()
        step(undoManager) { model.grade(.again) }
        model.input = "a0"
        step(undoManager) { model.submit() }
        #expect(model.isFinished)

        let before = document.deck
        model.practiceMistakes()
        #expect(model.isPracticing)
        #expect(!model.isFinished)
        model.input = "a0"
        step(undoManager) { model.submit() }
        #expect(model.isFinished)
        #expect(document.deck == before)
    }

    @Test func undoingPracticeReviewKeepsEarlierSessionIntact() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        step(undoManager) { model.submit() }
        step(undoManager) { model.grade(.again) }
        model.input = "a0"
        step(undoManager) { model.submit() }
        model.practiceMistakes()
        let scheduled = document.deck

        model.input = "a0"
        step(undoManager) { model.submit() }
        #expect(model.isFinished)
        undoManager.undo()
        #expect(!model.isFinished)
        #expect(model.isPracticing)
        #expect(document.deck == scheduled)
        undoManager.redo()
        #expect(model.isFinished)
    }

    /// A study session with a mistake, then a practice review of it. Nothing else holds the
    /// model, as in the app once the view closes the session.
    private func practicedMistake(in document: VocabularyDocument, undoManager: UndoManager) -> SessionViewModel {
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        step(undoManager) { model.submit() }
        step(undoManager) { model.grade(.again) }
        model.input = "a0"
        step(undoManager) { model.submit() }
        model.practiceMistakes()
        model.input = "a0"
        step(undoManager) { model.submit() }
        return model
    }

    /// The undo manager doesn't hold the target of an undo action (#174).
    @Test func undoingPracticeReviewOfAClosedSessionChangesNothing() {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        var model: SessionViewModel? = practicedMistake(in: document, undoManager: undoManager)
        weak var closed = model
        model = nil
        #expect(closed == nil)
        let scheduled = document.deck

        undoManager.undo()
        #expect(document.deck == scheduled)
        undoManager.redo()
        #expect(document.deck == scheduled)
    }

    @Test func redoingPracticeReviewOfAClosedSessionChangesNothing() {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        var model: SessionViewModel? = practicedMistake(in: document, undoManager: undoManager)
        let scheduled = document.deck
        undoManager.undo()
        #expect(model?.isPracticing == true)
        weak var closed = model
        model = nil
        #expect(closed == nil)

        undoManager.redo()
        #expect(document.deck == scheduled)
    }

    /// The undo actions don't hold their undo manager (#181).
    @Test func practiceReviewLetsItsUndoManagerGo() {
        let document = makeDocument(cards: 1)
        weak var released: UndoManager?
        autoreleasepool {
            let undoManager = makeUndoManager(for: document)
            let model = practicedMistake(in: document, undoManager: undoManager)
            #expect(model.isFinished)
            released = undoManager
        }
        #expect(released == nil)
    }

    @Test func reviewOfAClosedSessionIsUndoneAndRedone() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        var model: SessionViewModel? = SessionViewModel(document: document, autoAdvance: true)
        let card = try #require(model?.currentCard)
        model?.input = card.answer
        step(undoManager) { model?.submit() }
        let reviewed = try #require(document.card(withID: card.id))
        weak var closed = model
        model = nil
        #expect(closed == nil)

        undoManager.undo()
        #expect(document.card(withID: card.id) == card)
        undoManager.redo()
        #expect(document.card(withID: card.id) == reviewed)
    }

    @Test(arguments: [false, true])
    func removingTheCurrentCardMovesOn(whileShowingFeedback: Bool) throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let current = try #require(model.currentCard)
        if whileShowingFeedback {
            model.input = "wrong"
            model.submit()
            #expect(model.stage == .feedback(.wrong, response: "wrong"))
        }
        step(undoManager) { document.delete([current.id]) }
        #expect(model.currentCard != nil)
        #expect(model.currentCard?.id != current.id)
        #expect(model.session.totalCount == 1)
        #expect(model.stage == .asking)
        #expect(model.input.isEmpty)
        #expect(model.suggestedGrade == nil)
    }

    /// The session used to notice removals only by a changed number of cards (#57).
    @Test func removingTheCurrentCardMovesOnEvenIfTheCountStays() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)
        let current = try #require(model.currentCard)
        step(undoManager) {
            document.delete([current.id])
            document.add(CardText(question: "kot", answer: "Katze")!)
        }
        #expect(document.deck.cards.count == 2)
        #expect(model.currentCard != nil)
        #expect(model.currentCard?.id != current.id)
        #expect(model.stage == .asking)
        #expect(model.session.totalCount == 1)
    }

    @Test func undoingAnEditChangesTheCurrentCard() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager(for: document)
        let card = document.deck.cards[0]
        step(undoManager) { document.editText(of: card.id, to: CardText(question: "dom", answer: card.answer)!) }
        let model = SessionViewModel(document: document, autoAdvance: true)
        #expect(model.currentCard?.question == "dom")

        undoManager.undo()
        #expect(model.currentCard?.question == "q0")
    }

    @Test func undoingAndRedoingAnAnswerEditRechecksFeedback() {
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager(for: document)
        step(undoManager) { document.editText(of: card.id, to: CardText(question: card.question, answer: "Heim")!) }
        let model = SessionViewModel(document: document, autoAdvance: false)
        model.input = "Heim"
        model.submit()
        #expect(model.stage == .feedback(.correct, response: "Heim"))
        let questionNumber = model.questionNumber
        model.input = "not submitted"

        undoManager.undo()
        #expect(model.currentCard == card)
        #expect(model.stage == .feedback(.wrong, response: "Heim"))
        #expect(model.suggestedGrade == .again)
        #expect(model.session.reviewCount == 0)
        #expect(model.questionNumber == questionNumber)

        undoManager.redo()
        #expect(model.currentCard == card.withAnswer("Heim"))
        #expect(model.stage == .feedback(.correct, response: "Heim"))
        #expect(model.suggestedGrade == .good)
        #expect(model.session.reviewCount == 0)
        #expect(model.questionNumber == questionNumber)
    }

    @Test func undoingAndRedoingCaseSensitivityRechecksWithoutAutoAdvance() {
        var options = LearningOptions()
        options.caseSensitive = false
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(learningOptions: options, cards: [card]))
        let undoManager = makeUndoManager(for: document)
        options.caseSensitive = true
        step(undoManager) { document.updateLearningOptions(options) }
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "haus"
        model.submit()
        #expect(model.stage == .feedback(.almostCorrect, response: "haus"))
        let questionNumber = model.questionNumber

        undoManager.undo()
        #expect(model.stage == .feedback(.correct, response: "haus"))
        #expect(model.suggestedGrade == .good)
        #expect(model.highlightedAnswer == nil)
        #expect(document.deck.cards == [card])
        #expect(model.currentCard == card)
        #expect(model.session.reviewCount == 0)
        #expect(model.questionNumber == questionNumber)

        undoManager.redo()
        #expect(model.stage == .feedback(.almostCorrect, response: "haus"))
        #expect(model.suggestedGrade == .again)
        #expect(model.highlightedAnswer?.filter(\.isMismatch).map(\.text) == ["H"])
        #expect(document.deck.cards == [card])
        #expect(model.currentCard == card)
        #expect(model.session.reviewCount == 0)
        #expect(model.questionNumber == questionNumber)
    }

    @Test func emptyResponseRevealsTheAnswer() {
        let document = makeDocument(cards: 1)
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.submit()
        #expect(model.stage == .feedback(.wrong, response: ""))
    }

    @Test func nothingDueMeansFinished() {
        let learningState = LearningState(phase: .review, stability: 10, difficulty: 5, lastReview: Date(), due: Date().addingTimeInterval(86400))
        let card = Card(question: "q", answer: "a", learningState: learningState)
        let model = SessionViewModel(document: VocabularyDocument(deck: Deck(cards: [card])))
        #expect(model.isFinished)
    }

    @Test func sessionsAcrossTheStartOfAStudyDay() throws {
        let calendar = StudyCalendar.testing
        let day = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        // 03:30, still the study day before.
        let clock = ManualClock(calendar.start(ofDay: day).addingTimeInterval(-30 * 60))
        var learningOptions = LearningOptions()
        learningOptions.steps = 1
        learningOptions.fuzzing = false
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [card]), clock: clock.studyClock, calendar: calendar)
        let undoManager = makeUndoManager(for: document)
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "Haus"
        step(undoManager) { model.submit() }
        let state = try #require(document.card(withID: card.id)?.learningState)
        #expect(state.phase == .review)
        #expect(state.lastReview == clock.now)
        #expect(document.deck.progress.map(\.day) == [day - 1])
        // The interval counts from the study day before, so the card is due earlier
        // than it would be after a review at 04:30.
        var random = SeededRandom(seed: 0)  // unused without fuzzing
        let interval = Scheduler(learningOptions: learningOptions, calendar: calendar).intervalDays(stability: state.stability, using: &random)
        #expect(state.due == calendar.start(ofDay: day - 1 + interval))

        clock.now = state.due.addingTimeInterval(-60)
        #expect(document.deck.dueCount(at: clock.now) == 0)
        model.continueStudying()
        #expect(model.isFinished)

        clock.now = state.due.addingTimeInterval(60)
        #expect(document.deck.dueCount(at: clock.now) == 1)
        model.continueStudying()
        #expect(model.currentCard?.id == card.id)
        model.input = "Haus"
        step(undoManager) { model.submit() }
        #expect(document.card(withID: card.id)?.learningState?.lastReview == clock.now)
        #expect(document.deck.progress.map(\.day) == [day - 1, day - 1 + interval])
    }

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
