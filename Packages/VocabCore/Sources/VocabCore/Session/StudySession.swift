import Foundation

/// A session over the due cards; its reviews change their learning state. It runs
/// as `SessionMode.study`.
public struct StudySession: Sendable {
    /// The state shared with practice. Only this type changes it.
    public private(set) var session: Session

    /// Fuzzes the intervals of reviews. Kept apart from the order of the session, so
    /// a review doesn't change which card comes next. As part of the session's value,
    /// undoing a review restores it: the same review again yields the same due date.
    private var fuzzing: SeededRandom

    /// A session over all cards of `deck` that are due at `now`.
    ///
    /// - Parameters:
    ///   - calendar: Counts the study days that order the cards. Each review gets a
    ///     calendar of its own, see `review(_:of:with:at:calendar:)`.
    ///   - random: Decides the selection and order of the cards and the fuzz of the
    ///     intervals; the same seed gives the same session.
    public init(deck: Deck, at now: Date, calendar: StudyCalendar, random: SeededRandom = SeededRandom()) {
        var random = random
        let ids = Self.selectCards(from: deck, at: now, calendar: calendar, using: &random)
        fuzzing = SeededRandom(seed: random.next())
        session = Session(cardIDs: ids, startedAt: now, random: random)
    }

    /// Reviews `card`, the current card, and moves on to the next one.
    ///
    /// The card leaves the session once it is in the review phase.
    ///
    /// - Parameter calendar: Counts the elapsed study days and the due date. It may
    ///   differ from the one the session started with, e.g. after the machine's time
    ///   zone changed (#186).
    /// - Returns: `card` after the review, to be stored in the deck; `nil` if `card`
    ///   isn't the current card, e.g. because the session is finished.
    mutating func review(_ grade: Grade, of card: Card, with learningOptions: LearningOptions, at now: Date, calendar: StudyCalendar) -> Card? {
        guard card.id == session.currentCardID else { return nil }
        let scheduler = Scheduler(learningOptions: learningOptions, calendar: calendar)
        let scheduled = scheduler.review(card, grade: grade, at: now, using: &fuzzing)
        session.record(grade, isDone: scheduled.learningState?.phase == .review, at: now)
        return scheduled
    }

    mutating func perform(_ command: SessionCommand) {
        session.perform(command)
    }

    /// How soon `selectCards` introduces a due card; the smallest comes first.
    /// Due reviews go before new cards, so new cards only fill the rest of a session
    /// and can't crowd out reviews whose recall probability keeps dropping.
    enum Urgency: Comparable {
        /// Cards in learning or relearning.
        case learning
        /// Cards in the review phase, lowest probability of recall first.
        case review(recallBucket: Double)
        case new
    }

    /// Recall probabilities are rounded down to steps of `1 / recallBuckets`, so
    /// review cards of similar urgency get mixed.
    static let recallBuckets = 50.0

    /// Due cards in the order of their `Urgency`, cards of the same urgency at
    /// random. At most `cardsPerSession` cards are selected.
    static func selectCards(from deck: Deck, at now: Date, calendar: StudyCalendar, using random: inout SeededRandom) -> [Card.ID] {
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        var newCardsLeft = deck.learningOptions.newCardsPerSession ?? Int.max
        var candidates: [(id: Card.ID, urgency: Urgency, tieBreak: UInt64)] = []

        for card in deck.cards where card.isDue(at: now) {
            let urgency: Urgency
            if let learningState = card.learningState {
                if learningState.phase == .review {
                    let r = scheduler.recallProbability(of: learningState, at: now)
                    urgency = .review(recallBucket: (r * recallBuckets).rounded(.down))
                } else {
                    urgency = .learning
                }
            } else {
                guard newCardsLeft > 0 else { continue }
                newCardsLeft -= 1
                urgency = .new
            }
            candidates.append((card.id, urgency, random.next()))
        }

        let ordered =
            candidates
            .sorted { ($0.urgency, $0.tieBreak) < ($1.urgency, $1.tieBreak) }
            .map(\.id)
        return Array(ordered.prefix(deck.learningOptions.cardsPerSession ?? Int.max))
    }
}
