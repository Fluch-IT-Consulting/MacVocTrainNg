import Foundation
import Observation
import VocabCore

/// Drives a study session in the style of flash cards (#258): shows the question,
/// reveals the answer on request and applies the grade the learner gives. There is no
/// response to check, so the app suggests no grade; the reviews record `.revealed`.
///
/// Like `SessionViewModel` on the Mac, it leaves applying grades and keeping the
/// session's place in step with undo and redo and with every other change to the deck
/// to a `SessionDriver` (#264).
@MainActor @Observable
final class StudyModel: Identifiable {
    enum Stage: Equatable {
        /// The question is shown.
        case asking
        /// The answer is shown too; waiting for a grade.
        case revealed
        case finished
    }

    let document: VocabularyDocument
    private let driver: SessionDriver
    private(set) var stage: Stage

    /// Uses the document's clock, so reviews and the snapshot they update fall on the
    /// same study day.
    init(document: VocabularyDocument) {
        self.document = document
        driver = SessionDriver(document: document, mode: Self.makeSession(for: document))
        stage = driver.session.isFinished ? .finished : .asking
        driver.delegate = self
    }

    /// Always a study session; `SessionMode` is how the core records its reviews.
    var mode: SessionMode { driver.mode }

    var session: Session { driver.session }

    /// The card being asked, as the deck holds it now.
    var currentCard: Card? { driver.currentCard }

    var isFinished: Bool { stage == .finished }

    func reveal() {
        guard stage == .asking else { return }
        stage = .revealed
    }

    func grade(_ grade: Grade) {
        guard stage == .revealed else { return }
        driver.grade(grade)
    }

    /// Starts a new session with the cards that are still due.
    func continueStudying() {
        driver.start(Self.makeSession(for: document))
    }

    private static func makeSession(for document: VocabularyDocument) -> SessionMode {
        .study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar, reviewMode: .revealed))
    }
}

extension StudyModel: SessionDriverDelegate {
    func sessionDriverDidMoveOn(_ driver: SessionDriver) {
        stage = session.isFinished ? .finished : .asking
    }
}
