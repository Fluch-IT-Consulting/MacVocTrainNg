import Foundation

/// Per-deck learning options.
public struct LearningOptions: Codable, Hashable, Sendable {
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
    private enum CodingKeys: String, CodingKey {
        case targetRecall, maximumInterval, steps, cardsPerSession, newCardsPerSession
        case caseSensitive, fuzzing, parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LearningOptions()
        targetRecall = try container.decodeIfPresent(Double.self, forKey: .targetRecall) ?? defaults.targetRecall
        maximumInterval = try container.decodeIfPresent(Int.self, forKey: .maximumInterval) ?? defaults.maximumInterval
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? defaults.steps
        cardsPerSession = container.contains(.cardsPerSession)
            ? try container.decodeIfPresent(Int.self, forKey: .cardsPerSession)
            : defaults.cardsPerSession
        newCardsPerSession = try container.decodeIfPresent(Int.self, forKey: .newCardsPerSession)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? defaults.caseSensitive
        fuzzing = try container.decodeIfPresent(Bool.self, forKey: .fuzzing) ?? defaults.fuzzing
        parameters = try container.decodeIfPresent(FSRSParameters.self, forKey: .parameters) ?? defaults.parameters
        sanitize()
    }

    /// Clamps values from hand-edited or corrupt files into usable ranges.
    mutating func sanitize() {
        if !targetRecall.isFinite { targetRecall = LearningOptions().targetRecall }
        targetRecall = min(max(targetRecall, Self.targetRecallRange.lowerBound), Self.targetRecallRange.upperBound)
        maximumInterval = max(1, maximumInterval)
        steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
        cardsPerSession = cardsPerSession.map { max(1, $0) }
        newCardsPerSession = newCardsPerSession.map { max(0, $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetRecall, forKey: .targetRecall)
        try container.encode(maximumInterval, forKey: .maximumInterval)
        try container.encode(steps, forKey: .steps)
        // Written as null when unlimited, so a missing key can mean "default".
        try container.encode(cardsPerSession, forKey: .cardsPerSession)
        try container.encode(newCardsPerSession, forKey: .newCardsPerSession)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        try container.encode(fuzzing, forKey: .fuzzing)
        try container.encode(parameters, forKey: .parameters)
    }
}

/// A collection of cards together with its learning options and progress, stored
/// as one package (see `DeckFile`).
public struct Deck: Codable, Hashable, Sendable {
    public var learningOptions: LearningOptions
    public var cards: [Card]
    /// One daily snapshot per study day on which the deck changed, oldest first.
    public var progress: [DailySnapshot]

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

    /// Records the current distribution of cards as the snapshot for `day`.
    public mutating func updateProgress(day: Int) {
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
