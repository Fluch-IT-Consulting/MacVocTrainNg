import Foundation
import Testing
import VocabCore

@testable import MacVocTrain

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
        weak let closed = model
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
        weak let closed = model
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
        weak let closed = model
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

    /// A review after the machine's time zone changed counts elapsed study days and the
    /// due date in the new zone, also in a session that started before (#186).
    @Test(arguments: [false, true])
    func reviewsAfterATimeZoneSwitchCountStudyDaysInTheNewZone(sessionStartedBefore: Bool) throws {
        let day = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        // 23:00 in New York, already 05:00 of the next day in Berlin.
        let clock = ManualClock(StudyCalendar.newYork.start(ofDay: day).addingTimeInterval(19 * 3600))
        // Last reviewed at 21:00 in New York, 03:00 in Berlin: the same study day in
        // New York, the one before in Berlin.
        let lastReview = clock.now.addingTimeInterval(-2 * 3600)
        let learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: lastReview, due: lastReview)
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        var learningOptions = LearningOptions()
        learningOptions.fuzzing = false
        let document = VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: [card]), clock: clock.studyClock, calendar: .testing)
        let undoManager = makeUndoManager(for: document)

        let earlier = sessionStartedBefore ? SessionViewModel(document: document, autoAdvance: true) : nil
        document.switchTimeZone(to: StudyCalendar.newYork.timeZone)
        let model = earlier ?? SessionViewModel(document: document, autoAdvance: true)
        model.input = "Haus"
        step(undoManager) { model.submit() }

        func review(in calendar: StudyCalendar) -> Card {
            var random = SeededRandom(seed: 0)  // unused without fuzzing
            return Scheduler(learningOptions: learningOptions, calendar: calendar).review(card, grade: .good, at: clock.now, using: &random)
        }
        let expected = review(in: .newYork)
        #expect(expected.learningState?.stability != review(in: .testing).learningState?.stability)
        #expect(expected.learningState?.due != review(in: .testing).learningState?.due)
        #expect(document.card(withID: card.id) == expected)
        #expect(document.deck.progress.map(\.day) == [day])
    }
}
