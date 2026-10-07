import Foundation

/// Reading and writing decks.
///
/// A deck is a package (a directory shown as one file):
///
/// ```
/// Stapel.voctrain/
///   deck.json       learning options, cards with their learning state, progress
///   reviews.jsonl   one line per review: {"card":"…","date":1791216000,"grade":3}
/// ```
///
/// `deck.json` is pretty-printed JSON with sorted keys, so it stays readable and
/// diffs well. Its keys are spelled out by the records at the end of this file and
/// nowhere else; the domain types know nothing about the format. The review log lives apart because it grows with every review: kept
/// in `deck.json` it made every autosave re-encode the whole log (#4).
///
/// Versions 1 (a single JSON file with the log inside each card) and 2 (the package
/// with the keys before the glossary of #23) date from before the first release and
/// are no longer read.
public enum DeckFile {
    public static let format = "com.mfluch.voctrain.deck"
    public static let currentVersion = 3
    public static let deckFileName = "deck.json"
    public static let reviewsFileName = "reviews.jsonl"

    public enum Error: Swift.Error, Equatable {
        case notADeck
        /// Written by a newer version of the app.
        case unsupportedVersion(Int)
        /// Written before the first release, in a format that is no longer read.
        case outdatedVersion(Int)
        /// A line of `reviews.jsonl` could not be read (1-based).
        case damagedReviewLog(line: Int)
    }

    // MARK: - Writing

    /// The package for `deck`.
    ///
    /// - Parameter reviewLog: Pass the same encoder for every save of a document,
    ///   so only reviews added since the last save are encoded.
    public static func fileWrapper(for deck: Deck, reviewLog: ReviewLogEncoder = ReviewLogEncoder()) throws -> FileWrapper {
        let deckFile = FileWrapper(regularFileWithContents: try encodeDeck(deck))
        deckFile.preferredFilename = deckFileName
        let reviewsFile = FileWrapper(regularFileWithContents: reviewLog.encode(deck.cards))
        reviewsFile.preferredFilename = reviewsFileName
        return FileWrapper(directoryWithFileWrappers: [deckFileName: deckFile, reviewsFileName: reviewsFile])
    }

    /// `deck.json`: everything except the review log.
    static func encodeDeck(_ deck: Deck) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Envelope(deck))
    }

    // MARK: - Reading

    /// Reads a package.
    public static func decode(_ wrapper: FileWrapper) throws -> Deck {
        guard wrapper.isDirectory else {
            // Only version 1 was a single file; its header reports it as outdated.
            _ = try decode(wrapper.regularFileContents ?? Data())
            throw Error.notADeck
        }
        guard let deckData = wrapper.fileWrappers?[deckFileName]?.regularFileContents else {
            throw Error.notADeck
        }
        var deck = try decode(deckData)
        if let reviews = wrapper.fileWrappers?[reviewsFileName]?.regularFileContents {
            try ReviewLogEncoder.attach(reviews, to: &deck.cards)
        }
        return deck
    }

    /// Reads the `deck.json` of a package, without the review log.
    public static func decode(_ data: Data) throws -> Deck {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let header = try? decoder.decode(Header.self, from: data)
        guard let header, header.format == format, let version = header.version else {
            throw Error.notADeck
        }
        guard version <= currentVersion else {
            throw Error.unsupportedVersion(version)
        }
        guard version == currentVersion else {
            throw Error.outdatedVersion(version)
        }

        return try decoder.decode(Envelope.self, from: data).deck()
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }
}

// MARK: - Records

/// The records of `deck.json`, one property per key. They convert from and to the
/// domain types; checking the values is left to those (`FSRSParameters(_:)`,
/// `LearningOptions.sanitize()`).
extension DeckFile {
    private struct Envelope: Codable {
        var format: String
        var version: Int
        var learningOptions: OptionsRecord
        var cards: [CardRecord]
        var progress: [SnapshotRecord]

        init(_ deck: Deck) {
            format = DeckFile.format
            version = currentVersion
            learningOptions = OptionsRecord(deck.learningOptions)
            cards = deck.cards.map(CardRecord.init)
            progress = deck.progress.map(SnapshotRecord.init)
        }

        func deck() throws -> Deck {
            Deck(
                learningOptions: try learningOptions.learningOptions(),
                cards: cards.map(\.card),
                progress: try progress.map { try $0.snapshot() }
            )
        }
    }

    /// Missing keys take the default, so options added later need no new version.
    private struct OptionsRecord: Codable {
        var targetRecall: Double
        var maximumInterval: Int
        var steps: Int
        var cardsPerSession: Int?
        var newCardsPerSession: Int?
        var caseSensitive: Bool
        var fuzzing: Bool
        var parameters: [Double]

        init(_ options: LearningOptions) {
            targetRecall = options.targetRecall
            maximumInterval = options.maximumInterval
            steps = options.steps
            cardsPerSession = options.cardsPerSession
            newCardsPerSession = options.newCardsPerSession
            caseSensitive = options.caseSensitive
            fuzzing = options.fuzzing
            parameters = options.parameters.weights
        }

        func learningOptions() throws -> LearningOptions {
            guard let parameters = FSRSParameters(parameters) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected \(FSRSParameters.count) finite FSRS weights."))
            }
            var options = LearningOptions()
            options.targetRecall = targetRecall
            options.maximumInterval = maximumInterval
            options.steps = steps
            options.cardsPerSession = cardsPerSession
            options.newCardsPerSession = newCardsPerSession
            options.caseSensitive = caseSensitive
            options.fuzzing = fuzzing
            options.parameters = parameters
            options.sanitize()
            return options
        }

        private enum CodingKeys: String, CodingKey {
            case targetRecall, maximumInterval, steps, cardsPerSession, newCardsPerSession
            case caseSensitive, fuzzing, parameters
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = OptionsRecord(LearningOptions())
            targetRecall = try container.decodeIfPresent(Double.self, forKey: .targetRecall) ?? defaults.targetRecall
            maximumInterval = try container.decodeIfPresent(Int.self, forKey: .maximumInterval) ?? defaults.maximumInterval
            steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? defaults.steps
            // A missing limit takes the default, null means unlimited.
            cardsPerSession =
                container.contains(.cardsPerSession)
                ? try container.decodeIfPresent(Int.self, forKey: .cardsPerSession)
                : defaults.cardsPerSession
            newCardsPerSession =
                container.contains(.newCardsPerSession)
                ? try container.decodeIfPresent(Int.self, forKey: .newCardsPerSession)
                : defaults.newCardsPerSession
            caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? defaults.caseSensitive
            fuzzing = try container.decodeIfPresent(Bool.self, forKey: .fuzzing) ?? defaults.fuzzing
            parameters = try container.decodeIfPresent([Double].self, forKey: .parameters) ?? defaults.parameters
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(targetRecall, forKey: .targetRecall)
            try container.encode(maximumInterval, forKey: .maximumInterval)
            try container.encode(steps, forKey: .steps)
            // Written as null when unlimited, so a missing key can mean the default.
            try container.encode(cardsPerSession, forKey: .cardsPerSession)
            try container.encode(newCardsPerSession, forKey: .newCardsPerSession)
            try container.encode(caseSensitive, forKey: .caseSensitive)
            try container.encode(fuzzing, forKey: .fuzzing)
            try container.encode(parameters, forKey: .parameters)
        }
    }

    /// A card without its review log, which `ReviewLogEncoder` stores apart.
    private struct CardRecord: Codable {
        var id: UUID
        var question: String
        var answer: String
        /// Left out when empty.
        var hint: String?
        /// Read as 1970 when missing.
        var created: Date?
        /// Left out while the card is new.
        var learningState: LearningStateRecord?

        init(_ card: Card) {
            id = card.id
            question = card.question
            answer = card.answer
            hint = card.hint.isEmpty ? nil : card.hint
            created = card.created
            learningState = card.learningState.map(LearningStateRecord.init)
        }

        var card: Card {
            Card(
                id: id,
                question: question,
                answer: answer,
                hint: hint ?? "",
                created: created ?? Date(timeIntervalSince1970: 0),
                learningState: learningState?.learningState
            )
        }
    }

    private struct LearningStateRecord: Codable {
        enum Phase: String, Codable {
            case learning, review, relearning

            init(_ phase: LearningPhase) {
                switch phase {
                case .learning: self = .learning
                case .review: self = .review
                case .relearning: self = .relearning
                }
            }

            var learningPhase: LearningPhase {
                switch self {
                case .learning: .learning
                case .review: .review
                case .relearning: .relearning
                }
            }
        }

        var phase: Phase
        var step: Int
        var stability: Double
        var difficulty: Double
        var lastReview: Date
        var due: Date
        var reviews: Int
        var lapses: Int

        init(_ state: LearningState) {
            phase = Phase(state.phase)
            step = state.step
            stability = state.stability
            difficulty = state.difficulty
            lastReview = state.lastReview
            due = state.due
            reviews = state.reviews
            lapses = state.lapses
        }

        var learningState: LearningState {
            LearningState(
                phase: phase.learningPhase,
                step: step,
                stability: stability,
                difficulty: difficulty,
                lastReview: lastReview,
                due: due,
                reviews: reviews,
                lapses: lapses
            )
        }
    }

    private struct SnapshotRecord: Codable {
        /// The study day as an ISO date, e.g. "2026-10-05".
        var day: String
        var bins: [Int]

        init(_ snapshot: DailySnapshot) {
            day = CivilDate(dayNumber: snapshot.day).isoString
            bins = snapshot.bins
        }

        func snapshot() throws -> DailySnapshot {
            guard let date = CivilDate(isoString: day) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid date \(day)"))
            }
            return DailySnapshot(day: date.dayNumber, bins: bins)
        }
    }
}
