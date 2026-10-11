import Foundation
import Observation
import VocabCore

/// Drives a session on the Mac: checks responses, moves on after a correct one if
/// asked to, practises the mistakes and finishes up. Applying grades and keeping the
/// session's place in step with undo and redo and with every other change to the deck
/// is left to a `SessionDriver`, which the iPhone app shares.
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
    private let driver: SessionDriver
    private(set) var stage: Stage
    private(set) var previous: PreviousReview?
    /// Counts the questions asked. The view gives each question a response field of
    /// its own, so ⌘Z can't reach the typing for an earlier one (#9).
    private(set) var questionNumber = 0
    var input = ""

    /// Uses the document's clock, so reviews and the snapshot they update fall on the same study day.
    init(document: VocabularyDocument, autoAdvance: Bool = Preferences.autoAdvance) {
        let study = StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar)
        self.document = document
        self.autoAdvance = autoAdvance
        driver = SessionDriver(document: document, mode: .study(study))
        stage = study.session.isFinished ? .finished : .asking
        driver.delegate = self
    }

    /// The running session; its mode decides how a review is recorded.
    var mode: SessionMode { driver.mode }

    /// The part of the session that study sessions and practice share.
    var session: Session { driver.session }

    /// The card being asked, as the deck holds it now. Undoing an edit of the card
    /// during the session shows up here.
    var currentCard: Card? { driver.currentCard }

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
        guard stage != .finished, let card = currentCard, driver.grade(grade) else { return }
        previous = PreviousReview(question: card.question, answer: card.answer, grade: grade)
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        driver.finishUp()
    }

    /// Practises the mistakes of this session once more, without
    /// affecting their schedule.
    func practiceMistakes() {
        let ids = session.mistakeIDs.filter { document.card(withID: $0) != nil }
        guard !ids.isEmpty else { return }
        previous = nil
        driver.start(.practice(Practice(practicing: ids, at: document.clock.now)))
    }

    /// Starts a new regular session with the cards that are still due.
    func continueStudying() {
        previous = nil
        driver.start(.study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar)))
    }
}

extension SessionViewModel: SessionDriverDelegate {
    func sessionDriverDidMoveOn(_ driver: SessionDriver) {
        input = ""
        questionNumber += 1
        stage = session.isFinished ? .finished : .asking
    }

    /// Checks the response shown again against the card as it is now, e.g. after
    /// undoing an edit of its answer.
    func sessionDriverCardDidChange(_ driver: SessionDriver) {
        if case let .feedback(_, response) = stage, let card = currentCard {
            stage = .feedback(checker.check(response, against: card.answer), response: response)
        }
    }

    func sessionDriverDidRestore(_ driver: SessionDriver) {
        previous = nil
    }
}
