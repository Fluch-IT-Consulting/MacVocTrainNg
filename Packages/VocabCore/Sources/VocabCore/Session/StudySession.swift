import Foundation

/// The state of one study session: which cards remain, which one is asked, and
/// how it went so far.
///
/// The session only tracks card IDs. Applying an answer to the card itself is the
/// job of `Scheduler`; the caller passes the rescheduled card back via `record`.
public struct StudySession: Sendable {
    public enum Mode: Sendable {
        /// Due cards; answers are scheduled with FSRS.
        case regular
        /// Extra drill of cards failed earlier; answers don't affect scheduling.
        case practice
    }

    public let id = UUID()
    public let mode: Mode
    public let startedAt: Date
    public private(set) var currentCardID: Card.ID?
    public private(set) var totalCount: Int
    public private(set) var answerCount = 0
    public private(set) var correctCount = 0
    /// Cards answered with `.again` at least once, in order of their first failure.
    public private(set) var failedCardIDs: [Card.ID] = []

    private var queue: SessionQueue
    private let learningSteps: Int
    private var practiceStreaks: [Card.ID: Int] = [:]
    private var random: SeededRandom

    /// A regular session over all cards of `deck` that are due at `now`.
    public init(deck: Deck, at now: Date = Date(), random: SeededRandom = SeededRandom()) {
        var random = random
        let ids = Self.selectCards(from: deck, at: now, using: &random)
        self.init(mode: .regular, cardIDs: ids, learningSteps: deck.settings.learningSteps, startedAt: now, random: random)
    }

    /// A practice session over the given cards.
    public init(practicing cardIDs: [Card.ID], learningSteps: Int, at now: Date = Date(), random: SeededRandom = SeededRandom()) {
        var random = random
        self.init(mode: .practice, cardIDs: cardIDs.shuffled(using: &random), learningSteps: learningSteps, startedAt: now, random: random)
    }

    private init(mode: Mode, cardIDs: [Card.ID], learningSteps: Int, startedAt: Date, random: SeededRandom) {
        self.mode = mode
        self.startedAt = startedAt
        self.learningSteps = max(1, learningSteps)
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

    /// Records the answer to the current card and moves on to the next one.
    ///
    /// - Parameter scheduledCard: In a regular session, the current card after the
    ///   scheduler applied `grade`. It leaves the session once it has graduated.
    public mutating func record(_ grade: Grade, scheduledCard: Card? = nil) {
        guard let id = currentCardID else { return }
        answerCount += 1
        if grade.isRecall {
            correctCount += 1
        } else if !failedCardIDs.contains(id) {
            failedCardIDs.append(id)
        }

        let isDone: Bool
        switch mode {
        case .regular:
            isDone = scheduledCard?.memory?.phase == .review
        case .practice:
            if grade.isRecall {
                let streak = practiceStreaks[id, default: 0] + 1
                practiceStreaks[id] = streak
                isDone = !failedCardIDs.contains(id) || streak >= learningSteps
            } else {
                practiceStreaks[id] = 0
                isDone = false
            }
        }
        if isDone {
            queue.remove(id)
        }
        advance()
    }

    /// Stops introducing new cards; only cards already asked are finished.
    public mutating func finishUp() {
        queue.finishUp()
        totalCount = completedCount + queue.count
        if let id = currentCardID, !queue.contains(id) {
            advance()
        }
    }

    /// Drops the current card without recording an answer, e.g. because it was deleted.
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
    static func selectCards(from deck: Deck, at now: Date, using random: inout SeededRandom) -> [Card.ID] {
        let fsrs = FSRS(parameters: deck.settings.parameters)
        var newCardsLeft = deck.settings.newCardsPerSession ?? Int.max
        var candidates: [(id: Card.ID, priority: Double, tieBreak: UInt64)] = []

        for card in deck.cards where card.isDue(at: now) {
            let priority: Double
            if let memory = card.memory {
                if memory.phase == .review {
                    let elapsed = now.timeIntervalSince(memory.lastReview) / 86400
                    let r = fsrs.retrievability(elapsedDays: elapsed, stability: memory.stability)
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

        let ordered = candidates
            .sorted { ($0.priority, $0.tieBreak) < ($1.priority, $1.tieBreak) }
            .map(\.id)
        return Array(ordered.prefix(max(1, deck.settings.cardsPerSession ?? Int.max)))
    }
}
