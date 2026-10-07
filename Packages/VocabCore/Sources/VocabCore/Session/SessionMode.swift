import Foundation

/// A command that every mode passes on to its `Session` unchanged.
public enum SessionCommand: Sendable {
    /// Stops introducing new cards; only cards already asked are finished.
    case finishUp
    /// Drops the current card without recording a review, e.g. because it was deleted.
    case skip
}

/// The session that runs, as a study session or practice. The mode decides how a
/// review is recorded; it alone changes its session.
public enum SessionMode: Sendable {
    case study(StudySession)
    case practice(Practice)

    /// What grading the current card recorded.
    public enum Outcome: Equatable, Sendable {
        /// A study session rescheduled the card; the deck stores it.
        case rescheduled(Card)
        /// Practice counted the review; no card changes.
        case practiced
    }

    /// The part of the session that study sessions and practice share.
    public var session: Session {
        switch self {
        case let .study(study): study.session
        case let .practice(practice): practice.session
        }
    }

    /// Grades the current card and moves on to the next one.
    ///
    /// - Returns: `nil`, and the mode stays as it is, if the session is finished or
    ///   `deck` doesn't hold the current card.
    public mutating func grade(_ grade: Grade, in deck: Deck, at now: Date) -> Outcome? {
        guard let id = session.currentCardID, deck.card(withID: id) != nil else { return nil }
        switch self {
        case var .study(study):
            guard let card = study.review(grade, in: deck, at: now) else { return nil }
            self = .study(study)
            return .rescheduled(card)
        case var .practice(practice):
            practice.record(grade)
            self = .practice(practice)
            return .practiced
        }
    }

    /// Carries out `command` on the session.
    public mutating func perform(_ command: SessionCommand) {
        switch self {
        case var .study(study):
            study.perform(command)
            self = .study(study)
        case var .practice(practice):
            practice.perform(command)
            self = .practice(practice)
        }
    }
}
