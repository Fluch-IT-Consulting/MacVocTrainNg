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
    /// The running session; its mode decides how a review is recorded.
    private(set) var mode: SessionMode
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
        let study = StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar)
        self.document = document
        self.autoAdvance = autoAdvance
        mode = .study(study)
        stage = study.session.isFinished ? .finished : .asking
        refreshCurrentCard()
        deckObservation = document.deckDidChange.sink { [weak self] in
            self?.deckDidChange()
        }
    }

    /// The part of the session that study sessions and practice share.
    var session: Session { mode.session }

    var isPracticing: Bool {
        if case .practice = mode { true } else { false }
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
        let before = mode
        guard let outcome = mode.grade(grade, in: document.deck, at: document.clock.now) else { return }

        // One undo step takes back the card and the session's place. Practice changes
        // no card, but ⌘Z should still take back the last review instead of reaching a
        // review of the earlier session.
        undoManager?.beginUndoGrouping()
        if case let .rescheduled(scheduled) = outcome {
            document.applyReview(scheduled, undoManager: undoManager)
        }
        registerSessionUndo(from: before, to: mode, undoManager: undoManager)
        undoManager?.endUndoGrouping()

        previous = PreviousReview(question: card.question, answer: card.answer, grade: grade)
        moveOn()
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        mode.perform(.finishUp)
        moveOn()
    }

    /// Practises the mistakes of this session once more, without
    /// affecting their schedule.
    func practiceMistakes() {
        let ids = session.mistakeIDs.filter { document.card(withID: $0) != nil }
        guard !ids.isEmpty else { return }
        mode = .practice(Practice(practicing: ids, steps: document.deck.learningOptions.steps, at: document.clock.now))
        previous = nil
        moveOn()
    }

    /// Starts a new regular session with the cards that are still due.
    func continueStudying() {
        mode = .study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar))
        previous = nil
        moveOn()
    }

    private func moveOn() {
        input = ""
        questionNumber += 1
        // Cards deleted meanwhile can't be asked.
        while let id = session.currentCardID, document.card(withID: id) == nil {
            mode.perform(.skip)
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

    /// Undo runs the actions of a group backwards, so undoing a review restores the
    /// session before the document restores the card; `deckDidChange` then shows
    /// the card as it was. Redo runs them the other way round.
    private func registerSessionUndo(from before: SessionMode, to after: SessionMode, undoManager: UndoManager?) {
        undoManager?.registerMainActorUndo(withTarget: self, actionName: String(localized: "Review")) { model, undoManager in
            model.restore(before)
            model.registerSessionUndo(from: after, to: before, undoManager: undoManager)
        }
    }

    /// Called by undo/redo of a review.
    private func restore(_ snapshot: SessionMode) {
        guard snapshot.session.id == session.id else { return }  // a different session by now
        mode = snapshot
        previous = nil
        moveOn()
    }
}
