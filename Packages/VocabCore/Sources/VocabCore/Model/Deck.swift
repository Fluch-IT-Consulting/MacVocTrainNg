import Foundation

/// Per-deck learning options.
public struct DeckSettings: Codable, Hashable, Sendable {
    /// Probability of recall at which a card becomes due (FSRS "desired retention").
    public var desiredRetention: Double = 0.9
    /// Upper bound for review intervals in days.
    public var maximumInterval: Int = 36500
    /// Correct answers required before a new or forgotten card leaves the session.
    public var learningSteps: Int = 2
    /// Maximum number of cards per session; `nil` means unlimited.
    public var cardsPerSession: Int? = 100
    /// Maximum number of never-studied cards per session; `nil` means unlimited.
    public var newCardsPerSession: Int? = nil
    public var caseSensitive: Bool = true
    /// Spreads review intervals slightly so cards learned together don't stay clustered.
    public var fuzzing: Bool = true
    public var parameters: FSRSParameters = .default

    public init() {}

    public static let retentionRange: ClosedRange<Double> = 0.7...0.97
    public static let learningStepsRange: ClosedRange<Int> = 1...5
}

extension DeckSettings {
    private enum CodingKeys: String, CodingKey {
        case desiredRetention, maximumInterval, learningSteps, cardsPerSession, newCardsPerSession
        case caseSensitive, fuzzing, parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DeckSettings()
        desiredRetention = try container.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? defaults.desiredRetention
        maximumInterval = try container.decodeIfPresent(Int.self, forKey: .maximumInterval) ?? defaults.maximumInterval
        learningSteps = try container.decodeIfPresent(Int.self, forKey: .learningSteps) ?? defaults.learningSteps
        cardsPerSession = container.contains(.cardsPerSession)
            ? try container.decodeIfPresent(Int.self, forKey: .cardsPerSession)
            : defaults.cardsPerSession
        newCardsPerSession = try container.decodeIfPresent(Int.self, forKey: .newCardsPerSession)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? defaults.caseSensitive
        fuzzing = try container.decodeIfPresent(Bool.self, forKey: .fuzzing) ?? defaults.fuzzing
        parameters = try container.decodeIfPresent(FSRSParameters.self, forKey: .parameters) ?? defaults.parameters
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desiredRetention, forKey: .desiredRetention)
        try container.encode(maximumInterval, forKey: .maximumInterval)
        try container.encode(learningSteps, forKey: .learningSteps)
        // Written as null when unlimited, so a missing key can mean "default".
        try container.encode(cardsPerSession, forKey: .cardsPerSession)
        try container.encode(newCardsPerSession, forKey: .newCardsPerSession)
        try container.encode(caseSensitive, forKey: .caseSensitive)
        try container.encode(fuzzing, forKey: .fuzzing)
        try container.encode(parameters, forKey: .parameters)
    }
}

/// A collection of cards together with its settings and learning history.
/// This is the content of one document.
public struct Deck: Codable, Hashable, Sendable {
    public var settings: DeckSettings
    public var cards: [Card]
    /// One entry per study day on which the deck changed, oldest first.
    public var history: [DailySnapshot]

    public init(settings: DeckSettings = DeckSettings(), cards: [Card] = [], history: [DailySnapshot] = []) {
        self.settings = settings
        self.cards = cards
        self.history = history
    }

    public func index(of id: Card.ID) -> Int? {
        cards.firstIndex { $0.id == id }
    }

    public func card(withID id: Card.ID) -> Card? {
        index(of: id).map { cards[$0] }
    }

    /// Records the current distribution of cards as the snapshot for `day`.
    public mutating func updateHistory(day: Int) {
        let snapshot = DailySnapshot(day: day, bins: StabilityBins.histogram(of: cards))
        if let last = history.last, last.day == day {
            history[history.count - 1] = snapshot
        } else if let last = history.last, last.day > day {
            // Clock moved backwards; never reorder existing history.
            return
        } else {
            history.append(snapshot)
        }
    }
}
