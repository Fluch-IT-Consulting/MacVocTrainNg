import Foundation
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

@MainActor
struct DocumentTests {
    @Test func addingIsUndoable() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        let card = Card(question: "dom", answer: "Haus")

        step(undoManager) { document.add(card, undoManager: undoManager) }
        #expect(document.deck.cards == [card])
        #expect(undoManager.undoActionName == "Add Card" || undoManager.undoActionName == "Karte hinzufügen")

        undoManager.undo()
        #expect(document.deck.cards.isEmpty)
        undoManager.redo()
        #expect(document.deck.cards == [card])
    }

    @Test func deletingRestoresOriginalPositions() {
        let cards = (0..<5).map { Card(question: "q\($0)", answer: "a\($0)") }
        let document = VocabularyDocument(deck: Deck(cards: cards))
        let undoManager = makeUndoManager()

        step(undoManager) { document.delete([cards[1].id, cards[3].id], undoManager: undoManager) }
        #expect(document.deck.cards.map(\.question) == ["q0", "q2", "q4"])

        undoManager.undo()
        #expect(document.deck.cards == cards)
    }

    @Test func editingAndResettingAreUndoable() {
        var card = Card(question: "dom", answer: "Haus")
        card.learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: Date(), due: Date())
        let document = VocabularyDocument(deck: Deck(cards: [card]))
        let undoManager = makeUndoManager()

        var edited = card
        edited.answer = "Haus / Heim"
        step(undoManager) { document.update(edited, undoManager: undoManager) }
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
        document.update(card, undoManager: undoManager) // would throw without an open group if it registered anything
        #expect(!undoManager.canUndo)
    }

    @Test func changesUpdateTodaysSnapshot() {
        let document = VocabularyDocument()
        let undoManager = makeUndoManager()
        step(undoManager) { document.add(Card(question: "dom", answer: "Haus"), undoManager: undoManager) }
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
}

@MainActor
struct StudyViewModelTests {
    private func makeDocument(cards: Int, steps: Int = 1) -> VocabularyDocument {
        var learningOptions = LearningOptions()
        learningOptions.steps = steps
        learningOptions.fuzzing = false
        return VocabularyDocument(deck: Deck(learningOptions: learningOptions, cards: (0..<cards).map { Card(question: "q\($0)", answer: "a\($0)") }))
    }

    @Test func correctResponseMovesOnAndCanBeUndone() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = StudyViewModel(document: document, autoAdvance: true)
        let first = try #require(model.currentCard)

        model.input = first.answer
        step(undoManager) { model.submit(undoManager: undoManager) }
        #expect(document.card(withID: first.id)?.learningState?.phase == .review)
        #expect(model.previous?.grade == .good)
        #expect(model.currentCard?.id != first.id)
        #expect(model.session.completedCount == 1)

        undoManager.undo()
        #expect(document.card(withID: first.id)?.isNew == true)
        #expect(model.currentCard?.id == first.id)
        #expect(model.session.completedCount == 0)
        #expect(model.stage == .asking)

        undoManager.redo()
        #expect(document.card(withID: first.id)?.learningState?.phase == .review)
        #expect(model.currentCard?.id != first.id)
    }

    @Test func wrongResponseAsksForGrade() throws {
        let document = makeDocument(cards: 2, steps: 2)
        let undoManager = makeUndoManager()
        let model = StudyViewModel(document: document, autoAdvance: true)
        let card = try #require(model.currentCard)

        model.input = "nonsense"
        model.submit(undoManager: undoManager)
        #expect(model.stage == .feedback(.wrong, response: "nonsense"))
        #expect(model.suggestedGrade == .again)
        #expect(document.card(withID: card.id)?.isNew == true) // nothing applied yet

        step(undoManager) { model.grade(.again, undoManager: undoManager) }
        #expect(document.card(withID: card.id)?.learningState?.phase == .learning)
        #expect(model.session.mistakeIDs == [card.id])
        #expect(model.stage == .asking)
    }

    @Test func typoCanBeAcceptedAsCorrect() throws {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "Tag", answer: "dzień")]))
        let undoManager = makeUndoManager()
        let model = StudyViewModel(document: document, autoAdvance: true)

        model.input = "dzien"
        model.submit(undoManager: undoManager)
        #expect(model.stage == .feedback(.almostCorrect, response: "dzien"))
        step(undoManager) { model.grade(.good, undoManager: undoManager) }
        #expect(document.deck.cards[0].log.map(\.grade) == [.good])
    }

    @Test func withoutAutoAdvanceCorrectResponsesAreConfirmed() {
        let document = makeDocument(cards: 1)
        let model = StudyViewModel(document: document, autoAdvance: false)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.suggestedGrade == .good)
        model.grade(.easy, undoManager: nil)
        #expect(document.deck.cards[0].log.map(\.grade) == [.easy])
        #expect(model.isFinished)
    }

    @Test func practicingMistakesLeavesScheduleAlone() throws {
        let document = makeDocument(cards: 1)
        let model = StudyViewModel(document: document, autoAdvance: true)
        model.input = "wrong"
        model.submit(undoManager: nil)
        model.grade(.again, undoManager: nil)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.isFinished)

        let before = document.deck
        model.practiceMistakes()
        #expect(model.session.mode == .practice)
        #expect(!model.isFinished)
        model.input = "a0"
        model.submit(undoManager: nil)
        #expect(model.isFinished)
        #expect(document.deck == before)
    }

    @Test func undoingPracticeReviewKeepsEarlierSessionIntact() throws {
        let document = makeDocument(cards: 1)
        let undoManager = makeUndoManager()
        let model = StudyViewModel(document: document, autoAdvance: true)
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
        #expect(model.session.mode == .practice)
        #expect(document.deck == scheduled)
        undoManager.redo()
        #expect(model.isFinished)
    }

    @Test func removingTheCurrentCardMovesOn() throws {
        let document = makeDocument(cards: 2)
        let undoManager = makeUndoManager()
        let model = StudyViewModel(document: document, autoAdvance: true)
        let current = try #require(model.currentCard)
        step(undoManager) { document.delete([current.id], undoManager: undoManager) }
        model.documentDidChange()
        #expect(model.currentCard != nil)
        #expect(model.currentCard?.id != current.id)
        #expect(model.session.totalCount == 1)
    }

    @Test func emptyResponseRevealsTheAnswer() {
        let document = makeDocument(cards: 1)
        let model = StudyViewModel(document: document, autoAdvance: true)
        model.submit(undoManager: nil)
        #expect(model.stage == .feedback(.wrong, response: ""))
    }

    @Test func nothingDueMeansFinished() {
        var card = Card(question: "q", answer: "a")
        card.learningState = LearningState(phase: .review, stability: 10, difficulty: 5, lastReview: Date(), due: Date().addingTimeInterval(86400))
        let model = StudyViewModel(document: VocabularyDocument(deck: Deck(cards: [card])))
        #expect(model.isFinished)
    }
}
