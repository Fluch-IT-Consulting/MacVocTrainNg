import Combine
import Foundation
import Observation
import VocabCore

/// Drives a study session in the style of flash cards (#258): shows the question,
/// reveals the answer on request and applies the grade the learner gives. There is no
/// response to check, so the app suggests no grade; the reviews record `.revealed`.
///
/// Like `SessionViewModel` on the Mac, it keeps the session's place in step with undo
/// and redo of its reviews and with every other change to the deck. It doesn't share
/// that model, which is built around checking typed responses.
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
    /// Always a study session; `SessionMode` is how the core records its reviews.
    private(set) var mode: SessionMode
    private(set) var stage: Stage
    /// The card being asked, as the deck holds it now.
    private(set) var currentCard: Card?
    @ObservationIgnored private var deckObservation: AnyCancellable?

    /// Uses the document's clock, so reviews and the snapshot they update fall on the
    /// same study day.
    init(document: VocabularyDocument) {
        self.document = document
        mode = Self.makeSession(for: document)
        stage = .asking
        deckObservation = document.deckDidChange.sink { [weak self] in
            self?.deckDidChange()
        }
        moveOn()
    }

    var session: Session { mode.session }

    var isFinished: Bool { stage == .finished }

    func reveal() {
        guard stage == .asking else { return }
        stage = .revealed
    }

    func grade(_ grade: Grade) {
        guard stage == .revealed else { return }
        let before = mode
        guard case let .rescheduled(change) = mode.grade(grade, in: document.deck, at: document.clock.now, calendar: document.calendar) else { return }
        // One undo action takes back the card and the session's place: the document
        // restores the card, then the session.
        document.applyReview(change, alongside: sessionRestore(from: before, to: mode))
        moveOn()
    }

    /// Starts a new session with the cards that are still due.
    func continueStudying() {
        mode = Self.makeSession(for: document)
        moveOn()
    }

    private static func makeSession(for document: VocabularyDocument) -> SessionMode {
        .study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar, reviewMode: .revealed))
    }

    private func moveOn() {
        // Cards deleted meanwhile, e.g. by a merge, can't be asked.
        while let id = session.currentCardID, document.card(withID: id) == nil {
            mode.perform(.skip)
        }
        currentCard = session.currentCardID.flatMap(document.card(withID:))
        stage = session.isFinished ? .finished : .asking
    }

    /// Runs after every change to the deck, the session's own reviews included.
    private func deckDidChange() {
        if let id = session.currentCardID, document.card(withID: id) == nil {
            moveOn()
        } else {
            currentCard = session.currentCardID.flatMap(document.card(withID:))
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

    private func restore(_ snapshot: SessionMode) {
        guard snapshot.session.id == session.id else { return }  // a different session by now
        mode = snapshot
        moveOn()
    }
}
