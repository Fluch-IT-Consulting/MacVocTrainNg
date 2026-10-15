import Foundation
import Testing

@testable import VocTrain
@testable import VocabCore

@MainActor
struct StudyModelTests {
    let created = Date(timeIntervalSince1970: 1_791_216_000)

    func makeDocument(questions: [String] = ["dom", "kot"]) throws -> (VocabularyDocument, UndoManager) {
        let cards = questions.map { Card(text: CardText(question: $0, answer: "x")!, created: created) }
        let document = try VocabularyDocument(deck: Deck(cards: cards), clock: StudyClock { [created] in created.addingTimeInterval(60) })
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        document.undoManager = undoManager
        return (document, undoManager)
    }

    /// Grades in an undo group of its own, like one tap in the app.
    func grade(_ model: StudyModel, _ grade: Grade, undoManager: UndoManager) {
        undoManager.beginUndoGrouping()
        model.grade(grade)
        undoManager.endUndoGrouping()
    }

    @Test func gradingNeedsTheAnswerShown() throws {
        let (document, undoManager) = try makeDocument()
        let model = StudyModel(document: document)
        #expect(model.stage == .asking)

        grade(model, .good, undoManager: undoManager)
        #expect(model.session.reviewCount == 0)
        #expect(document.deck.cards.allSatisfy { $0.isNew })

        model.reveal()
        #expect(model.stage == .revealed)
    }

    @Test func reviewsAreRecordedAsRevealed() throws {
        let (document, undoManager) = try makeDocument()
        let model = StudyModel(document: document)
        let id = try #require(model.currentCard?.id)

        model.reveal()
        grade(model, .good, undoManager: undoManager)
        #expect(document.card(withID: id)?.log.map(\.mode) == [.revealed])
        #expect(document.card(withID: id)?.log.map(\.grade) == [.good])
        #expect(model.session.reviewCount == 1)
        #expect(model.stage == .asking)
    }

    @Test func undoTakesBackTheCardAndTheSessionsPlace() throws {
        let (document, undoManager) = try makeDocument()
        let model = StudyModel(document: document)
        let card = try #require(model.currentCard)

        model.reveal()
        grade(model, .again, undoManager: undoManager)
        undoManager.undo()
        #expect(document.card(withID: card.id) == card)
        #expect(model.currentCard == card)
        #expect(model.session.reviewCount == 0)
        #expect(model.stage == .asking)

        undoManager.redo()
        #expect(document.card(withID: card.id)?.log.map(\.grade) == [.again])
        #expect(model.session.reviewCount == 1)
    }

    /// On the iPhone too, a card can be suspended in the session, revealed or not (#290).
    @Test func suspendingMovesOnAndCanBeUndone() throws {
        let (document, undoManager) = try makeDocument()
        let model = StudyModel(document: document)
        let card = try #require(model.currentCard)
        #expect(!model.hasUndoableSteps)

        model.reveal()
        undoManager.beginUndoGrouping()
        model.suspendCurrentCard()
        undoManager.endUndoGrouping()
        #expect(document.card(withID: card.id)?.isSuspended == true)
        #expect(document.card(withID: card.id)?.learningState == nil)
        #expect(model.currentCard?.id != card.id)
        #expect(model.stage == .asking)
        #expect(model.hasUndoableSteps)

        undoManager.undo()
        #expect(document.card(withID: card.id) == card)
        #expect(model.currentCard == card)
        #expect(!model.hasUndoableSteps)
    }

    @Test func sessionWithoutDueCardsIsFinished() throws {
        let (document, _) = try makeDocument(questions: [])
        let model = StudyModel(document: document)
        #expect(model.isFinished)
        #expect(model.currentCard == nil)
    }
}
