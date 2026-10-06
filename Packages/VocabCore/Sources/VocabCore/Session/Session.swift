import Foundation

/// The state of one session, a study session or practice: which cards remain,
/// which one is asked, and how it went so far.
///
/// The session only tracks card IDs. Applying a grade to the card itself is the
/// job of `Scheduler`; in a study session the caller passes the rescheduled card
/// back via `record(_:scheduledCard:)`. Practice changes no card and records its
/// reviews with `recordPractice(_:)`.
public struct Session: Sendable {
    public enum Mode: Sendable {
        /// Due cards; reviews change their learning state.
        case study
        /// The mistakes of an earlier session; reviews change no learning state.
        case practice
    }

    public let id = UUID()
    public let mode: Mode
    public let startedAt: Date
    public private(set) var currentCardID: Card.ID?
    public private(set) var totalCount: Int
    public private(set) var reviewCount = 0
    public private(set) var recalledCount = 0
    /// Cards graded `.again` at least once, in order of their first `.again`.
    public private(set) var mistakeIDs: [Card.ID] = []

    private var queue: SessionQueue
    private let steps: Int
    /// Steps of practice mistakes, counted like steps in a study session.
    private var practiceSteps: [Card.ID: Steps] = [:]
    private var random: SeededRandom

    /// A regular session over all cards of `deck` that are due at `now`.
    public init(deck: Deck, at now: Date, calendar: StudyCalendar = StudyCalendar(), random: SeededRandom = SeededRandom()) {
        var random = random
        let ids = Self.selectCards(from: deck, at: now, calendar: calendar, using: &random)
        self.init(mode: .study, cardIDs: ids, steps: deck.learningOptions.steps, startedAt: now, random: random)
    }

    /// A practice session over the given cards.
    public init(practicing cardIDs: [Card.ID], steps: Int, at now: Date, random: SeededRandom = SeededRandom()) {
        var random = random
        self.init(mode: .practice, cardIDs: cardIDs.shuffled(using: &random), steps: steps, startedAt: now, random: random)
    }

    private init(mode: Mode, cardIDs: [Card.ID], steps: Int, startedAt: Date, random: SeededRandom) {
        self.mode = mode
        self.startedAt = startedAt
        self.steps = steps
        self.random = random
        queue = SessionQueue(cardIDs: cardIDs)
        totalCount = cardIDs.count
        advance()
    }

    public var isFinished: Bool { currentCardID == nil }
    public var remainingCount: Int { queue.count }
    public var completedCount: Int { totalCount - queue.count }
    /// Cards already asked that would still be finished by `finishUp()`.
    public var startedCount: Int { queue.startedCount }

    /// Records the review of the current card in a study session and moves on to
    /// the next one.
    ///
    /// - Parameter scheduledCard: The current card after the scheduler applied
    ///   `grade`. It leaves the session once it is in the review phase.
    public mutating func record(_ grade: Grade, scheduledCard: Card) {
        precondition(mode == .study, "Practice records reviews with recordPractice(_:)")
        guard let id = currentCardID else { return }
        precondition(scheduledCard.id == id, "scheduledCard must be the current card")
        count(grade, of: id)
        if scheduledCard.learningState?.phase == .review {
            queue.remove(id)
        }
        advance()
    }

    /// Records the review of the current card in practice and moves on to the next one.
    public mutating func recordPractice(_ grade: Grade) {
        precondition(mode == .practice, "A study session records reviews with record(_:scheduledCard:)")
        guard let id = currentCardID else { return }
        count(grade, of: id)
        // Mistakes need steps like (re)learning cards in a study session;
        // other cards leave after one recall like cards in the review phase.
        var isDone = true
        if mistakeIDs.contains(id) {
            var mistakeSteps = practiceSteps[id] ?? Steps(required: steps)
            mistakeSteps.apply(grade)
            practiceSteps[id] = mistakeSteps
            isDone = mistakeSteps.areEnough
        }
        if isDone {
            queue.remove(id)
        }
        advance()
    }

    private mutating func count(_ grade: Grade, of id: Card.ID) {
        reviewCount += 1
        if grade.isRecall {
            recalledCount += 1
        } else if !mistakeIDs.contains(id) {
            mistakeIDs.append(id)
        }
    }

    /// Stops introducing new cards; only cards already asked are finished.
    public mutating func finishUp() {
        let completed = completedCount
        queue.finishUp()
        totalCount = completed + queue.count
        if let id = currentCardID, !queue.contains(id) {
            advance()
        }
    }

    /// Drops the current card without recording a review, e.g. because it was deleted.
    public mutating func skip() {
        guard let id = currentCardID else { return }
        queue.remove(id)
        totalCount -= 1
        advance()
    }

    /// Ends the session immediately.
    public mutating func stop() {
        currentCardID = nil
    }

    private mutating func advance() {
        currentCardID = queue.next(using: &random)
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
