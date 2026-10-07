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

    /// The running session; its type decides how a review is recorded.
    enum Mode {
        case study(StudySession)
        case practice(Practice)

        var session: Session {
            get {
                switch self {
                case let .study(study): study.session
                case let .practice(practice): practice.session
                }
            }
            set {
                switch self {
                case var .study(study):
                    study.session = newValue
                    self = .study(study)
                case var .practice(practice):
                    practice.session = newValue
                    self = .practice(practice)
                }
            }
        }
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
    private(set) var mode: Mode
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

        switch mode {
        case var .study(study):
            guard let scheduled = study.review(grade, in: document.deck, at: document.clock.now) else { return }
            mode = .study(study)
            let after = mode
            let hook = UndoHook(
                forward: { [weak self] in self?.restore(after) },
                backward: { [weak self] in self?.restore(before) }
            )
            document.applyReview(scheduled, undoManager: undoManager, hook: hook)
        case var .practice(practice):
            // Practice doesn't touch the cards, but ⌘Z should still take back the
            // last review instead of reaching a review of the earlier session.
            practice.record(grade)
            mode = .practice(practice)
            registerSessionUndo(from: before, to: mode, undoManager: undoManager)
        }

        previous = PreviousReview(question: card.question, answer: card.answer, grade: grade)
        moveOn()
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        mode.session.finishUp()
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
            mode.session.skip()
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

    private func registerSessionUndo(from before: Mode, to after: Mode, undoManager: UndoManager?) {
        undoManager?.registerMainActorUndo(withTarget: self, actionName: String(localized: "Review")) { model, undoManager in
            model.restore(before)
            model.registerSessionUndo(from: after, to: before, undoManager: undoManager)
        }
    }

    /// Called by undo/redo of a review.
    private func restore(_ snapshot: Mode) {
        guard snapshot.session.id == session.id else { return }  // a different session by now
        mode = snapshot
        previous = nil
        moveOn()
    }
}
