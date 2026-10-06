import Foundation

/// A session over the due cards; its reviews change their learning state.
///
/// Applying a grade to the card itself is the job of `Scheduler`; the caller passes
/// the rescheduled card back via `record(_:scheduledCard:)`.
public struct StudySession: Sendable {
    /// The state shared with practice; `finishUp()`, `skip()` and `stop()` act on it.
    public var session: Session

    /// A session over all cards of `deck` that are due at `now`.
    public init(deck: Deck, at now: Date, calendar: StudyCalendar = StudyCalendar(), random: SeededRandom = SeededRandom()) {
        var random = random
        let ids = Self.selectCards(from: deck, at: now, calendar: calendar, using: &random)
        session = Session(cardIDs: ids, startedAt: now, random: random)
    }

    /// Records the review of the current card and moves on to the next one.
    ///
    /// - Parameter scheduledCard: The current card after the scheduler applied
    ///   `grade`. It leaves the session once it is in the review phase.
    public mutating func record(_ grade: Grade, scheduledCard: Card) {
        guard let id = session.currentCardID else { return }
        precondition(scheduledCard.id == id, "scheduledCard must be the current card")
        session.record(grade, isDone: scheduledCard.learningState?.phase == .review)
    }

    /// Due cards in the order they should be introduced: cards in (re)learning
    /// first, then new cards, then reviews with the lowest probability of recall.
    /// At most `cardsPerSession` cards are selected.
    static func selectCards(from deck: Deck, at now: Date, calendar: StudyCalendar, using random: inout SeededRandom) -> [Card.ID] {
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        var newCardsLeft = deck.learningOptions.newCardsPerSession ?? Int.max
        var candidates: [(id: Card.ID, priority: Double, tieBreak: UInt64)] = []

        for card in deck.cards where card.isDue(at: now) {
            let priority: Double
            if let learningState = card.learningState {
                if learningState.phase == .review {
                    let r = scheduler.recallProbability(of: learningState, at: now)
                    // Coarse buckets so cards of similar urgency get mixed.
                    priority = (r * 50).rounded(.down) / 50
                } else {
                    priority = -2
                }
            } else {
                guard newCardsLeft > 0 else { continue }
                newCardsLeft -= 1
                priority = -1
            }
            candidates.append((card.id, priority, random.next()))
        }

        let ordered =
            candidates
            .sorted { ($0.priority, $0.tieBreak) < ($1.priority, $1.tieBreak) }
            .map(\.id)
        return Array(ordered.prefix(max(1, deck.learningOptions.cardsPerSession ?? Int.max)))
    }
}
