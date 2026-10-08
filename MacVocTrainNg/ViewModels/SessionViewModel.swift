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
    /// The session the learner finished up. Finishing up has no undo of its own, so
    /// undo and redo of a review in it finish up again (#180).
    @ObservationIgnored private var finishedUpSessionID: UUID?
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

    /// The answer with what an almost correct response got wrong marked; `nil` for any
    /// other stage or result. Minds case only where the check did.
    var highlightedAnswer: [ResponseDiff.Segment]? {
        guard case let .feedback(.almostCorrect, response) = stage, let card = currentCard else { return nil }
        return ResponseDiff.segments(response: response, expected: card.answer, caseSensitive: checker.caseSensitive)
    }

    /// Checks responses with the deck's learning options.
    private var checker: ResponseChecker {
        ResponseChecker(caseSensitive: document.deck.learningOptions.caseSensitive)
    }

    /// Checks the response. An empty response counts as "I don't know".
    func submit() {
        guard stage == .asking, let card = currentCard else { return }
        let result = checker.check(input, against: card.answer)
        if result == .correct, autoAdvance {
            grade(.good)
        } else {
            stage = .feedback(result, response: input)
        }
    }

    func grade(_ grade: Grade) {
        guard stage != .finished, let card = currentCard else { return }
        let before = mode
        guard let outcome = mode.grade(grade, in: document.deck, at: document.clock.now) else { return }

        // One undo action takes back the card and the session's place: the document
        // restores the card, then the session. Practice changes no card, but ⌘Z should
        // still take back the last review instead of reaching a review of the earlier
        // session.
        let restore = sessionRestore(from: before, to: mode)
        switch outcome {
        case let .rescheduled(change):
            document.applyReview(change, alongside: restore)
        case .practiced:
            Self.registerUndo(restore, on: document)
        }

        previous = PreviousReview(question: card.question, answer: card.answer, grade: grade)
        moveOn()
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        mode.perform(.finishUp)
        finishedUpSessionID = session.id
        moveOn()
    }

    /// Practises the mistakes of this session once more, without
    /// affecting their schedule.
    func practiceMistakes() {
        let ids = session.mistakeIDs.filter { document.card(withID: $0) != nil }
        guard !ids.isEmpty else { return }
        mode = .practice(Practice(practicing: ids, at: document.clock.now))
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
            if case let .feedback(_, response) = stage, let card = currentCard {
                stage = .feedback(checker.check(response, against: card.answer), response: response)
            }
        }
    }

    /// Brings back the session's place before a review on undo and after it on redo.
    /// Holds the model weakly: the document's undo stack outlives a closed session.
    private func sessionRestore(from before: SessionMode, to after: SessionMode) -> UndoCompanion {
        UndoCompanion(
            undo: { [weak self] in self?.restore(before) },
            redo: { [weak self] in self?.restore(after) }
        )
    }

    /// Registers `companion` as the undo action of a practice review, which changes no
    /// card and so doesn't go through the document.
    ///
    /// It lands on the document's undo manager all the same, so NSDocument counts it as
    /// a change: the deck shows as edited and autosave writes it unchanged. Marking the
    /// action discardable doesn't prevent that. Accepted, because without the undo
    /// action ⌘Z would reach the last review of the earlier study session (#166).
    ///
    /// The target is the document, like for a review in a study session: the model may
    /// be gone before the undo stack, and the handler reaches it only through `companion`
    /// (#174).
    private static func registerUndo(_ companion: UndoCompanion, on document: VocabularyDocument) {
        document.undoManager?.registerMainActorUndo(withTarget: document, actionName: String(localized: "Review")) { document, _ in
            companion.undo()
            registerUndo(companion.reversed, on: document)
        }
    }

    /// Called by undo/redo of a review.
    private func restore(_ snapshot: SessionMode) {
        guard snapshot.session.id == session.id else { return }  // a different session by now
        mode = snapshot
        // A snapshot from before finishing up would bring back the cards not asked yet.
        if session.id == finishedUpSessionID {
            mode.perform(.finishUp)
        }
        previous = nil
        moveOn()
    }
}
