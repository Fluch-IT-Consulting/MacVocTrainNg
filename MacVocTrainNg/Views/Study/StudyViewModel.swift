import Foundation
import Observation
import VocabCore

/// Drives a study session: checks responses, applies grades to the document
/// and keeps the session's place in sync with undo and redo.
@MainActor @Observable
final class StudyViewModel {
    enum Stage: Equatable {
        /// Waiting for the response to the current card.
        case asking
        /// The response was checked; waiting for the learner to confirm a grade.
        case feedback(ResponseChecker.Result, response: String)
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
    private(set) var session: StudySession
    private(set) var stage: Stage
    private(set) var previous: PreviousReview?
    var input = ""

    init(document: VocabularyDocument, autoAdvance: Bool = Preferences.autoAdvance) {
        let session = StudySession(deck: document.deck)
        self.document = document
        self.autoAdvance = autoAdvance
        self.session = session
        stage = session.isFinished ? .finished : .asking
    }

    var isFinished: Bool { stage == .finished }

    var currentCard: Card? {
        session.currentCardID.flatMap(document.card(withID:))
    }

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
        case .regular:
            let scheduler = Scheduler(learningOptions: document.deck.learningOptions, calendar: document.calendar)
            let scheduled = scheduler.review(card, grade: grade, at: Date())
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
            session.record(grade)
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
        session = StudySession(practicing: ids, steps: document.deck.learningOptions.steps)
        previous = nil
        moveOn()
    }

    /// Starts a new regular session with the cards that are still due.
    func continueStudying() {
        session = StudySession(deck: document.deck)
        previous = nil
        moveOn()
    }

    private func moveOn() {
        input = ""
        // Cards deleted meanwhile can't be asked.
        while let id = session.currentCardID, document.card(withID: id) == nil {
            session.skip()
        }
        stage = session.isFinished ? .finished : .asking
    }

    /// Re-validates the current card after the document changed from outside the
    /// session, e.g. undoing "Add Card" removed the card being asked.
    func documentDidChange() {
        guard stage != .finished, let id = session.currentCardID, document.card(withID: id) == nil else { return }
        moveOn()
    }

    private func registerSessionUndo(from before: StudySession, to after: StudySession, undoManager: UndoManager?) {
        // Undo handlers run on the main thread, where the undo manager lives.
        nonisolated(unsafe) let undoManager = undoManager
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restore(before)
                model.registerSessionUndo(from: after, to: before, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(String(localized: "Review"))
    }

    /// Called by undo/redo of a review.
    private func restore(_ snapshot: StudySession) {
        guard snapshot.id == session.id else { return } // a different session by now
        session = snapshot
        previous = nil
        moveOn()
    }
}
