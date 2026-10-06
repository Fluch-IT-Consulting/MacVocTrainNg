import Combine
import Foundation
import Observation
import VocabCore

/// Drives a session: checks responses, applies grades to the document
/// and keeps the session's place in sync with undo and redo and with
/// every other change to the deck.
@MainActor @Observable
final class SessionViewModel {
    enum Stage: Equatable {
        /// Waiting for the response to the current card.
        case asking
        /// The response was checked; waiting for the learner to confirm a grade.
        case feedback(CheckResult, response: String)
        case finished
    }

    /// The card reviewed last, shown below the current one.
    struct PreviousReview: Equatable {
        var question: String
        var answer: String
        var grade: Grade
    }

    let document: VocabularyDocument
    /// Move on right after a correct response instead of asking for a grade.
    let autoAdvance: Bool
    private(set) var session: Session
    private(set) var stage: Stage
    /// The card being asked, as the deck holds it now. Undoing an edit of the card
    /// during the session shows up here.
    private(set) var currentCard: Card?
    private(set) var previous: PreviousReview?
    /// Counts the questions asked. The view gives each question a response field of
    /// its own, so ⌘Z can't reach the typing for an earlier one (#9).
    private(set) var questionNumber = 0
    var input = ""
    @ObservationIgnored private var deckObservation: AnyCancellable?

    /// Uses the document's clock, so reviews and the snapshot they update fall on the same study day.
    init(document: VocabularyDocument, autoAdvance: Bool = Preferences.autoAdvance) {
        let session = Session(deck: document.deck, at: document.clock.now, calendar: document.calendar)
        self.document = document
        self.autoAdvance = autoAdvance
        self.session = session
        stage = session.isFinished ? .finished : .asking
        refreshCurrentCard()
        deckObservation = document.deckDidChange.sink { [weak self] in
            self?.deckDidChange()
        }
    }

    var isFinished: Bool { stage == .finished }

    var suggestedGrade: Grade? {
        guard case let .feedback(result, _) = stage else { return nil }
        return result.suggestedGrade
    }

    /// Checks the response. An empty response counts as "I don't know".
    func submit(undoManager: UndoManager?) {
        guard stage == .asking, let card = currentCard else { return }
        let checker = ResponseChecker(caseSensitive: document.deck.learningOptions.caseSensitive)
        let result = checker.check(input, against: card.answer)
        if result == .correct, autoAdvance {
            grade(.good, undoManager: undoManager)
        } else {
            stage = .feedback(result, response: input)
        }
    }

    func grade(_ grade: Grade, undoManager: UndoManager?) {
        guard stage != .finished, let card = currentCard else { return }
        let before = session

        switch session.mode {
        case .study:
            let scheduler = Scheduler(learningOptions: document.deck.learningOptions, calendar: document.calendar)
            let scheduled = scheduler.review(card, grade: grade, at: document.clock.now)
            session.record(grade, scheduledCard: scheduled)
            let after = session
            let hook = UndoHook(
                forward: { [weak self] in self?.restore(after) },
                backward: { [weak self] in self?.restore(before) }
            )
            document.applyReview(scheduled, undoManager: undoManager, hook: hook)
        case .practice:
            // Practice doesn't touch the cards, but ⌘Z should still take back the
            // last review instead of reaching a review of the earlier session.
            session.recordPractice(grade)
            registerSessionUndo(from: before, to: session, undoManager: undoManager)
        }

        previous = PreviousReview(question: card.question, answer: card.answer, grade: grade)
        moveOn()
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        session.finishUp()
        moveOn()
    }

    /// Practises the mistakes of this session once more, without
    /// affecting their schedule.
    func practiceMistakes() {
        let ids = session.mistakeIDs.filter { document.card(withID: $0) != nil }
        guard !ids.isEmpty else { return }
        session = Session(practicing: ids, steps: document.deck.learningOptions.steps, at: document.clock.now)
        previous = nil
        moveOn()
    }

    /// Starts a new regular session with the cards that are still due.
    func continueStudying() {
        session = Session(deck: document.deck, at: document.clock.now, calendar: document.calendar)
        previous = nil
        moveOn()
    }

    private func moveOn() {
        input = ""
        questionNumber += 1
        // Cards deleted meanwhile can't be asked.
        while let id = session.currentCardID, document.card(withID: id) == nil {
            session.skip()
        }
        refreshCurrentCard()
        stage = session.isFinished ? .finished : .asking
    }

    private func refreshCurrentCard() {
        currentCard = session.currentCardID.flatMap(document.card(withID:))
    }

    /// Runs after every change to the deck, the session's own reviews included.
    /// Moves on if the card being asked is gone, e.g. because undoing "Add Card"
    /// removed it.
    private func deckDidChange() {
        if let id = session.currentCardID, document.card(withID: id) == nil {
            moveOn()
        } else {
            refreshCurrentCard()
        }
    }

    private func registerSessionUndo(from before: Session, to after: Session, undoManager: UndoManager?) {
        undoManager?.registerMainActorUndo(withTarget: self, actionName: String(localized: "Review")) { model, undoManager in
            model.restore(before)
            model.registerSessionUndo(from: after, to: before, undoManager: undoManager)
        }
    }

    /// Called by undo/redo of a review.
    private func restore(_ snapshot: Session) {
        guard snapshot.id == session.id else { return }  // a different session by now
        session = snapshot
        previous = nil
        moveOn()
    }
}
