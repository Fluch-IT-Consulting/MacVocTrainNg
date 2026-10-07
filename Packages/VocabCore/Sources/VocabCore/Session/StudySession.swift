import Foundation

/// A session over the due cards; its reviews change their learning state.
public struct StudySession: SessionMode {
    /// The state shared with practice. Only this type changes it.
    public private(set) var session: Session

    private let calendar: StudyCalendar
    /// Fuzzes the intervals of reviews. Kept apart from the order of the session, so
    /// a review doesn't change which card comes next. As part of the session's value,
    /// undoing a review restores it: the same review again yields the same due date.
    private var fuzzing: SeededRandom

    /// A session over all cards of `deck` that are due at `now`.
    ///
    /// - Parameter random: Decides the selection and order of the cards and the fuzz
    ///   of the intervals; the same seed gives the same session.
    public init(deck: Deck, at now: Date, calendar: StudyCalendar = StudyCalendar(), random: SeededRandom = SeededRandom()) {
        var random = random
        let ids = Self.selectCards(from: deck, at: now, calendar: calendar, using: &random)
        self.calendar = calendar
        fuzzing = SeededRandom(seed: random.next())
        session = Session(cardIDs: ids, startedAt: now, random: random)
    }

    /// Reviews the current card and moves on to the next one.
    ///
    /// The card is scheduled with the learning options `deck` has now, so a change
    /// to them during the session applies from the next review on. It leaves the
    /// session once it is in the review phase.
    ///
    /// - Returns: The current card after the review, to be stored in the deck; `nil`
    ///   if the session is finished or `deck` doesn't hold the current card.
    public mutating func review(_ grade: Grade, in deck: Deck, at now: Date) -> Card? {
        guard let id = session.currentCardID, let card = deck.card(withID: id) else { return nil }
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        let scheduled = scheduler.review(card, grade: grade, at: now, using: &fuzzing)
        session.record(grade, isDone: scheduled.learningState?.phase == .review)
        return scheduled
    }

    public mutating func perform(_ command: SessionCommand) {
        session.perform(command)
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
