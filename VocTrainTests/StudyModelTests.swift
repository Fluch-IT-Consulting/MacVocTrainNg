import Foundation
import Testing
import VocabCore

@testable import VocTrain

@MainActor
struct StudyModelTests {
    let created = Date(timeIntervalSince1970: 1_791_216_000)

    func makeDocument(questions: [String] = ["dom", "kot"]) -> (VocabularyDocument, UndoManager) {
        let cards = questions.map { Card(text: CardText(question: $0, answer: "x")!, created: created) }
        let document = VocabularyDocument(deck: Deck(cards: cards), clock: StudyClock { [created] in created.addingTimeInterval(60) })
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

    @Test func gradingNeedsTheAnswerShown() {
        let (document, undoManager) = makeDocument()
        let model = StudyModel(document: document)
        #expect(model.stage == .asking)

        grade(model, .good, undoManager: undoManager)
        #expect(model.session.reviewCount == 0)
        #expect(document.deck.cards.allSatisfy(\.isNew))

        model.reveal()
        #expect(model.stage == .revealed)
    }

    @Test func reviewsAreRecordedAsRevealed() throws {
        let (document, undoManager) = makeDocument()
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
        let (document, undoManager) = makeDocument()
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

    @Test func sessionWithoutDueCardsIsFinished() {
        let (document, _) = makeDocument(questions: [])
        let model = StudyModel(document: document)
        #expect(model.isFinished)
        #expect(model.currentCard == nil)
    }
}
