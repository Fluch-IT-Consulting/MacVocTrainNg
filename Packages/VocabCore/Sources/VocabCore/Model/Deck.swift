import Foundation

/// Per-deck learning options.
public struct LearningOptions: Hashable, Sendable {
    /// Recall probability at which a card becomes due again (FSRS "desired retention").
    public var targetRecall: Double = 0.9
    /// Upper bound for review intervals in days.
    public var maximumInterval: Int = 36500
    /// Steps (`.good` grades) a card in (re)learning needs to reach the review phase.
    public var steps: Int = 2
    /// Maximum number of cards per session; `nil` means unlimited.
    public var cardsPerSession: Int? = 100
    /// Maximum number of never-studied cards per session; `nil` means unlimited.
    public var newCardsPerSession: Int? = nil
    public var caseSensitive: Bool = true
    /// Spreads review intervals slightly so cards learned together don't stay clustered.
    public var fuzzing: Bool = true
    public var parameters: FSRSParameters = .default

    public init() {}

    public static let targetRecallRange: ClosedRange<Double> = 0.7...0.97
    public static let stepsRange: ClosedRange<Int> = 1...5
}

extension LearningOptions {
    /// Clamps values from hand-edited or corrupt files into usable ranges.
    mutating func sanitize() {
        if !targetRecall.isFinite { targetRecall = LearningOptions().targetRecall }
        targetRecall = min(max(targetRecall, Self.targetRecallRange.lowerBound), Self.targetRecallRange.upperBound)
        maximumInterval = max(1, maximumInterval)
        steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
        cardsPerSession = cardsPerSession.map { max(1, $0) }
        newCardsPerSession = newCardsPerSession.map { max(0, $0) }
    }
}

/// A collection of cards together with its learning options and progress, stored
/// as one package (see `DeckFile`).
///
/// Cards change only through `apply(_:day:)`, which keeps `progress` in step with them.
public struct Deck: Hashable, Sendable {
    public var learningOptions: LearningOptions
    public internal(set) var cards: [Card]
    /// One daily snapshot per study day on which the deck changed, oldest first.
    public internal(set) var progress: [DailySnapshot]

    public init(learningOptions: LearningOptions = LearningOptions(), cards: [Card] = [], progress: [DailySnapshot] = []) {
        self.learningOptions = learningOptions
        self.cards = cards
        self.progress = progress
    }

    public func index(of id: Card.ID) -> Int? {
        cards.firstIndex { $0.id == id }
    }

    public func card(withID id: Card.ID) -> Card? {
        index(of: id).map { cards[$0] }
    }

    /// The number of cards due at `date`.
    public func dueCount(at date: Date) -> Int {
        cards.reduce(0) { $0 + ($1.isDue(at: date) ? 1 : 0) }
    }

    /// Cards with the same question as `question`, see `CardText.key(forQuestion:)`.
    public func cards(withQuestion question: String) -> [Card] {
        let key = CardText.key(forQuestion: question)
        guard !key.isEmpty else { return [] }
        return cards.filter { CardText.key(forQuestion: $0.question) == key }
    }

    /// Records the current distribution of cards as the snapshot for `day`.
    mutating func updateProgress(day: Int) {
        let snapshot = DailySnapshot(day: day, bins: StabilityBins.histogram(of: cards))
        if let last = progress.last, last.day == day {
            progress[progress.count - 1] = snapshot
        } else if let last = progress.last, last.day > day {
            // Clock moved backwards; never reorder existing snapshots.
            return
        } else {
            progress.append(snapshot)
        }
    }
}
