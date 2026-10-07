import Combine
import Foundation
import Observation
import Testing
import VocabCore

@testable import MacVocTrain

/// An undo manager that groups explicitly, as there is no event loop in tests.
@MainActor
private func makeUndoManager() -> UndoManager {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    return undoManager
}

@MainActor
private func step(_ undoManager: UndoManager, _ action: () -> Void) {
    undoManager.beginUndoGrouping()
    action()
    undoManager.endUndoGrouping()
}

/// Counts calls of a sendable closure. Only used on the main actor.
private final class ChangeCount: @unchecked Sendable {
    var value = 0
}

@MainActor
struct DocumentTests {
    @Test func addingIsUndoable() throws {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()

        var id: Card.ID?
        step(undoManager) { id = document.add(CardText(question: " dom", answer: "Haus ", hint: "Gebäude")!, undoManager: undoManager) }
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

        let first = document.add(CardText(question: "dom", answer: "Haus")!, undoManager: nil)
        #expect(document.card(withID: first)?.created == clock.now)

        clock.now.addTimeInterval(3600)
        let second = document.add(CardText(question: "kot", answer: "Katze")!, undoManager: nil)
        #expect(document.card(withID: second)?.created == clock.now)
    }

    @Test func importIsOneUndoableChange() {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus")]))
        let undoManager = makeUndoManager()
        let imported = [Card(question: "kot", answer: "Katze"), Card(question: "pies", answer: "Hund")]

        step(undoManager) { document.importCards(imported, undoManager: undoManager) }
        #expect(document.deck.cards.map(\.question) == ["dom", "kot", "pies"])
        #expect(undoManager.undoActionName == "Import Cards" || undoManager.undoActionName == "Karten importieren")

        undoManager.undo()
        #expect(document.deck.cards.map(\.question) == ["dom"])
    }

    @Test func editingAndResettingAreUndoable() {
        let learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: Date(), due: Date())
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager()

        var edited = card
        edited.answer = "Haus / Heim"
        step(undoManager) { document.editText(of: card.id, to: CardText(question: "dom", answer: "Haus / Heim")!, undoManager: undoManager) }
        #expect(document.deck.cards[0] == edited)
        step(undoManager) { document.resetLearningState(of: [card.id], undoManager: undoManager) }
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
        let undoManager = makeUndoManager()
        document.editText(of: card.id, to: CardText(question: " dom", answer: "Haus")!, undoManager: undoManager)  // would throw without an open group if it registered anything
        #expect(!undoManager.canUndo)
    }

    @Test func changesAreAnnouncedBeforeAndReportedAfter() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        var events: [String] = []
        let willChange = document.objectWillChange.sink { events.append("will \(document.deck.cards.count)") }
        let didChange = document.deckDidChange.sink { events.append("did \(document.deck.cards.count)") }

        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!, undoManager: undoManager) }
        undoManager.undo()
        #expect(events == ["will 0", "did 1", "will 1", "did 0"])
        _ = (willChange, didChange)
    }

    @Test func changesUpdateTodaysSnapshot() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!, undoManager: undoManager) }
        #expect(document.deck.progress.last?.day == document.calendar.dayNumber(for: Date()))
        #expect(document.deck.progress.last?.total == 1)
    }

    @Test func snapshotSavesReadableDeck() throws {
        // The file stores dates with second precision.
        let created = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus", created: created)]))
        let snapshot = try document.snapshot(contentType: .vocabularyDeck)
        #expect(try DeckFile.decode(DeckFile.fileWrapper(for: snapshot)) == document.deck)
    }

    /// The first save of a new deck takes the snapshot on a background thread.
    @Test func snapshotOffTheMainThreadHoldsTheLatestChange() async throws {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!, undoManager: undoManager) }
        let snapshot = try await Task.detached { try document.snapshot(contentType: .vocabularyDeck) }.value
        #expect(snapshot == document.deck)
    }

    @Test func newParametersReplayMemoryInOneUndoableChange() throws {
        let scheduler = Scheduler(learningOptions: LearningOptions())
        let start = Date(timeIntervalSince1970: 1_791_216_000)
        var random = SeededRandom(seed: 1)
        let studied = [(0.0, Grade.good), (60.0, .good), (20.0 * 86400, .good)].reduce(Card(question: "dom", answer: "Haus")) {
            scheduler.review($0, grade: $1.1, at: start.addingTimeInterval($1.0), using: &random)
        }
        let document = VocabularyDocument(deck: Deck(cards: [studied]))
        let undoManager = makeUndoManager()

        var options = LearningOptions()
        var weights = FSRSParameters.default.weights
        weights[8] = 1.2
        options.parameters = try #require(FSRSParameters(weights))
        step(undoManager) { document.updateLearningOptions(options, undoManager: undoManager) }
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
        let undoManager = makeUndoManager()
        document.updateLearningOptions(LearningOptions(), undoManager: undoManager)  // would throw without an open group if it registered anything
        #expect(!undoManager.canUndo)
    }
}

@MainActor
struct SessionViewModelTests {
    private func makeDocument(cards: Int, steps: Int = 1) -> VocabularyDocument {
        var learningOptions = LearningOptions()
        learningOptions.steps = steps
        learningOptions.fuzzing = false
        return VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: (0..<cards).map { Card(question: "q\($0)", answer: "a\($0)") }))
    }

    @Test func correctResponseMovesOnAndCanBeUndone() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)

        model.input = first.answer
        step(undoManager) { model.submit(undoManager: undoManager) }
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
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)
        model.input = first.answer
        step(undoManager) { model.submit(undoManager: undoManager) }

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
        var reviewCount: Int
        var stage: SessionViewModel.Stage

        @MainActor init(_ model: SessionViewModel) {
            cards = model.document.deck.cards
            currentCardID = model.currentCard?.id
            completedCount = model.session.completedCount
            reviewCount = model.session.reviewCount
            stage = model.stage
        }
    }

    /// Each undo and redo registers the opposite step anew; the stack must stay in order.
    @Test func severalReviewsAreUndoneAndRedoneOneByOne() throws {
        let document = makeDocument(cards: 3)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        var places = [Place(model)]
        for _ in 0..<3 {
            model.input = try #require(model.currentCard).answer
            step(undoManager) { model.submit(undoManager: undoManager) }
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
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let card = try #require(model.currentCard)
        model.input = card.answer
        step(undoManager) { model.submit(undoManager: undoManager) }
        #expect(model.isFinished)

        undoManager.undo()
        #expect(model.stage == .asking)
        #expect(model.currentCard == card)

        undoManager.redo()
        #expect(model.isFinished)
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
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [card]), clock: ManualClock(now).studyClock)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "Haus"
        step(undoManager) { model.submit(undoManager: undoManager) }
        #expect(document.card(withID: card.id)?.learningState?.step == 1)
        #expect(model.currentCard?.id == card.id)  // stays in the session

        model.input = "Haus"
        step(undoManager) { model.submit(undoManager: undoManager) }
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
        step(undoManager) { model.submit(undoManager: undoManager) }
        #expect(document.card(withID: card.id)?.learningState == reviewed)
    }

    @Test func aNewReviewAfterUndoDropsTheRedo() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)
        model.input = first.answer
        step(undoManager) { model.submit(undoManager: undoManager) }

        undoManager.undo()
        #expect(model.currentCard == first)
        model.input = "wrong"
        model.submit(undoManager: undoManager)
        step(undoManager) { model.grade(.again, undoManager: undoManager) }
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
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let card = try #require(model.currentCard)

        model.input = "nonsense"
        model.submit(undoManager: undoManager)
        #expect(model.stage == .feedback(.wrong, response: "nonsense"))
        #expect(model.suggestedGrade == .again)
        #expect(document.card(withID: card.id)?.isNew == true)  // nothing applied yet

        step(undoManager) { model.grade(.again, undoManager: undoManager) }
        #expect(document.card(withID: card.id)?.learningState?.phase == .learning)
        #expect(model.session.mistakeIDs == [card.id])
        #expect(model.stage == .asking)
    }

    @Test func typoCanBeAcceptedAsCorrect() throws {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "Tag", answer: "dzień")]))
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "dzien"
        model.submit(undoManager: undoManager)
        #expect(model.stage == .feedback(.almostCorrect, response: "dzien"))
        step(undoManager) { model.grade(.good, undoManager: undoManager) }
        #expect(document.deck.cards[0].log.map(\.grade) == [.good])
    }

    @Test func withoutAutoAdvanceCorrectResponsesAreConfirmed() {
        let document = makeDocument(cards: 1)
        let model = SessionViewModel(document: document, autoAdvance: false)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.suggestedGrade == .good)
        model.grade(.easy, undoManager: nil)
        #expect(document.deck.cards[0].log.map(\.grade) == [.easy])
        #expect(model.isFinished)
    }

    @Test func practicingMistakesLeavesScheduleAlone() throws {
        let document = makeDocument(cards: 1)
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        model.submit(undoManager: nil)
        model.grade(.again, undoManager: nil)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.isFinished)

        let before = document.deck
        model.practiceMistakes()
        #expect(model.isPracticing)
        #expect(!model.isFinished)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.isFinished)
        #expect(document.deck == before)
    }

    @Test func undoingPracticeReviewKeepsEarlierSessionIntact() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        step(undoManager) { model.submit(undoManager: undoManager) }
        step(undoManager) { model.grade(.again, undoManager: undoManager) }
        model.input = "a0"
        step(undoManager) { model.submit(undoManager: undoManager) }
        model.practiceMistakes()
        let scheduled = document.deck

        model.input = "a0"
        step(undoManager) { model.submit(undoManager: undoManager) }
        #expect(model.isFinished)
        undoManager.undo()
        #expect(!model.isFinished)
        #expect(model.isPracticing)
        #expect(document.deck == scheduled)
        undoManager.redo()
        #expect(model.isFinished)
    }

    @Test func removingTheCurrentCardMovesOn() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let current = try #require(model.currentCard)
        step(undoManager) { document.delete([current.id], undoManager: undoManager) }
        #expect(model.currentCard != nil)
        #expect(model.currentCard?.id != current.id)
        #expect(model.session.totalCount == 1)
    }

    /// The session used to notice removals only by a changed number of cards (#57).
    @Test func removingTheCurrentCardMovesOnEvenIfTheCountStays() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = SessionViewModel(document: document, autoAdvance: true)
        let current = try #require(model.currentCard)
        step(undoManager) {
            document.delete([current.id], undoManager: undoManager)
            document.add(CardText(question: "kot", answer: "Katze")!, undoManager: undoManager)
        }
        #expect(document.deck.cards.count == 2)
        #expect(model.currentCard != nil)
        #expect(model.currentCard?.id != current.id)
        #expect(model.stage == .asking)
        #expect(model.session.totalCount == 1)
    }

    @Test func undoingAnEditChangesTheCurrentCard() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager()
        let card = document.deck.cards[0]
        step(undoManager) { document.editText(of: card.id, to: CardText(question: "dom", answer: card.answer)!, undoManager: undoManager) }
        let model = SessionViewModel(document: document, autoAdvance: true)
        #expect(model.currentCard?.question == "dom")

        undoManager.undo()
        #expect(model.currentCard?.question == "q0")
    }

    @Test func emptyResponseRevealsTheAnswer() {
        let document = makeDocument(cards: 1)
        let model = SessionViewModel(document: document, autoAdvance: true)
        model.submit(undoManager: nil)
        #expect(model.stage == .feedback(.wrong, response: ""))
    }

    @Test func nothingDueMeansFinished() {
        let learningState = LearningState(phase: .review, stability: 10, difficulty: 5, lastReview: Date(), due: Date().addingTimeInterval(86400))
        let card = Card(question: "q", answer: "a", learningState: learningState)
        let model = SessionViewModel(document: VocabularyDocument(deck: Deck(cards: [card])))
        #expect(model.isFinished)
    }

    @Test func sessionsAcrossTheStartOfAStudyDay() throws {
        let calendar = StudyCalendar()
        let day = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        // 03:30, still the study day before.
        let clock = ManualClock(calendar.start(ofDay: day).addingTimeInterval(-30 * 60))
        var learningOptions = LearningOptions()
        learningOptions.steps = 1
        learningOptions.fuzzing = false
        let card = Card(question: "dom", answer: "Haus")
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [card]), clock: clock.studyClock)
        let model = SessionViewModel(document: document, autoAdvance: true)

        model.input = "Haus"
        model.submit(undoManager: nil)
        let state = try #require(document.card(withID: card.id)?.learningState)
        #expect(state.phase == .review)
        #expect(state.lastReview == clock.now)
        #expect(document.deck.progress.map(\.day) == [day - 1])
        // The interval counts from the study day before, so the card is due earlier
        // than it would be after a review at 04:30.
        var random = SeededRandom(seed: 0)  // unused without fuzzing
        let interval = Scheduler(learningOptions: learningOptions).intervalDays(stability: state.stability, using: &random)
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
        model.submit(undoManager: nil)
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

    @Test func dueCardsAreCountedAfterEveryChange() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        #expect(document.dueCards.count == 0)

        step(undoManager) { document.add(CardText(question: "dom", answer: "Haus")!, undoManager: undoManager) }
        #expect(document.dueCards.count == 1)
        undoManager.undo()
        #expect(document.dueCards.count == 0)
    }

    @Test func dueCardsTellObserversOnlyWhenTheNumberChanges() {
        let clock = ManualClock(Date(timeIntervalSince1970: 1_791_216_000))
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "dom", answer: "Haus")]), clock: clock.studyClock)
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

        document.add(CardText(question: "kot", answer: "Katze")!, undoManager: nil)
        #expect(changes.value == 1)
    }
}
