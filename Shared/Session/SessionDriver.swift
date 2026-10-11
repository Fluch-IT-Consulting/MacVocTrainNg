import Combine
import Foundation
import Observation
import VocabCore

/// Runs a session over the deck of a document, for `SessionViewModel` on the Mac and
/// `StudyModel` on the iPhone (#264): applies grades to the document and keeps the
/// session's place in step with undo and redo of its reviews and with every other
/// change to the deck, e.g. a merge that deleted the card being asked.
///
/// What a model adds, like checking typed responses or revealing the answer, it does
/// around the driver. The driver tells it through its delegate when it moved on.
@MainActor @Observable
final class SessionDriver {
    let document: VocabularyDocument
    /// The running session; its mode decides how a review is recorded.
    private(set) var mode: SessionMode
    /// The card being asked, as the deck holds it now. Undoing an edit of the card
    /// during the session shows up here.
    private(set) var currentCard: Card?
    @ObservationIgnored weak var delegate: (any SessionDriverDelegate)?
    /// The session the learner finished up. Finishing up has no undo of its own, so
    /// undo and redo of a review in it finish up again (#180).
    @ObservationIgnored private var finishedUpSessionID: UUID?
    @ObservationIgnored private var deckObservation: AnyCancellable?

    /// Starts with the current card of `mode`'s session. Tells the delegate of no move:
    /// it isn't set yet.
    init(document: VocabularyDocument, mode: SessionMode) {
        self.document = document
        self.mode = mode
        skipDeletedCards()
        refreshCurrentCard()
        deckObservation = document.deckDidChange.sink { [weak self] in
            self?.deckDidChange()
        }
    }

    /// The part of the session that study sessions and practice share.
    var session: Session { mode.session }

    /// Grades the card being asked and moves on. One undo action takes back the review
    /// and the session's place: the document restores the card, then the session.
    /// Practice changes no card, but undo should still take back the last review
    /// instead of reaching a review of the earlier session.
    ///
    /// - Returns: Whether the session recorded the review; it doesn't once it is
    ///   finished.
    @discardableResult
    func grade(_ grade: Grade) -> Bool {
        let before = mode
        guard let outcome = mode.grade(grade, in: document.deck, at: document.clock.now, calendar: document.calendar) else { return false }
        let restore = sessionRestore(from: before, to: mode)
        switch outcome {
        case let .rescheduled(change):
            document.applyReview(change, alongside: restore)
        case .practiced:
            Self.registerUndo(restore, on: document)
        }
        moveOn()
        return true
    }

    /// Only finishes the cards already asked.
    func finishUp() {
        mode.perform(.finishUp)
        finishedUpSessionID = session.id
        moveOn()
    }

    /// Runs `mode` from now on, e.g. practice of the mistakes or a new study session.
    func start(_ mode: SessionMode) {
        self.mode = mode
        moveOn()
    }

    /// Moves to the current card of the session, past cards deleted meanwhile, and
    /// tells the delegate.
    private func moveOn() {
        skipDeletedCards()
        refreshCurrentCard()
        delegate?.sessionDriverDidMoveOn(self)
    }

    /// Cards deleted meanwhile, e.g. by undoing "Add Card" or by a merge, can't be asked.
    private func skipDeletedCards() {
        while let id = session.currentCardID, document.card(withID: id) == nil {
            mode.perform(.skip)
        }
    }

    private func refreshCurrentCard() {
        currentCard = session.currentCardID.flatMap(document.card(withID:))
    }

    /// Runs after every change to the deck, the session's own reviews included. Moves
    /// on if the card being asked is gone.
    private func deckDidChange() {
        if let id = session.currentCardID, document.card(withID: id) == nil {
            moveOn()
        } else {
            refreshCurrentCard()
            delegate?.sessionDriverCardDidChange(self)
        }
    }

    /// Brings back the session's place before a review on undo and after it on redo.
    /// Holds the driver weakly: the document's undo stack outlives a closed session.
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
    /// The target is the document, like for a review in a study session: the driver may
    /// be gone before the undo stack, and the handler reaches it only through `companion`
    /// (#174).
    private static func registerUndo(_ companion: UndoCompanion, on document: VocabularyDocument) {
        document.undoManager?.registerMainActorUndo(withTarget: document, actionName: String(localized: "Review")) { document, _ in
            companion.undo()
            registerUndo(companion.reversed, on: document)
        }
    }

    /// Called by undo and redo of a review.
    private func restore(_ snapshot: SessionMode) {
        guard snapshot.session.id == session.id else { return }  // a different session by now
        mode = snapshot
        // A snapshot from before finishing up would bring back the cards not asked yet.
        if session.id == finishedUpSessionID {
            mode.perform(.finishUp)
        }
        delegate?.sessionDriverDidRestore(self)
        moveOn()
    }
}

/// What a model around a `SessionDriver` hears of. Each call comes after the driver's
/// `mode` and `currentCard` hold the new state.
@MainActor
protocol SessionDriverDelegate: AnyObject {
    /// The driver moved on to the next card, or to the end of the session: after a
    /// grade, a new mode, finishing up, undo or redo, or because the card being asked
    /// was deleted.
    func sessionDriverDidMoveOn(_ driver: SessionDriver)
    /// The deck changed, but the card being asked is still there; `currentCard` holds
    /// it as the deck does now.
    func sessionDriverCardDidChange(_ driver: SessionDriver)
    /// Undo or redo brought back the session's place before or after a review; the
    /// driver moves on right after.
    func sessionDriverDidRestore(_ driver: SessionDriver)
}

extension SessionDriverDelegate {
    func sessionDriverCardDidChange(_ driver: SessionDriver) {}
    func sessionDriverDidRestore(_ driver: SessionDriver) {}
}
