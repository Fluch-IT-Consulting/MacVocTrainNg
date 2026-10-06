import Foundation

/// Reading and writing decks.
///
/// Since version 2 a deck is a package (a directory shown as one file):
///
/// ```
/// Stapel.voctrain/
///   deck.json       learning options, cards with their learning state, progress
///   reviews.jsonl   one line per review: {"card":"…","date":1791216000,"grade":3}
/// ```
///
/// `deck.json` is pretty-printed JSON with sorted keys, so it stays readable and
/// diffs well. The review log lives apart because it grows with every review: kept
/// in `deck.json` it made every autosave re-encode the whole log (#4).
///
/// Version 1 was a single JSON file with the log inside each card. It is still read
/// and becomes a package on the next save.
public enum DeckFile {
    public static let format = "com.mfluch.voctrain.deck"
    public static let currentVersion = 2
    public static let deckFileName = "deck.json"
    public static let reviewsFileName = "reviews.jsonl"

    public enum Error: Swift.Error, Equatable {
        case notADeck
        case unsupportedVersion(Int)
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
        let envelope = Envelope(
            format: format,
            version: currentVersion,
            learningOptions: deck.learningOptions,
            cards: deck.cards,
            progress: deck.progress
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.userInfo[.omitReviewLog] = true
        return try encoder.encode(envelope)
    }

    // MARK: - Reading

    /// Reads a package (version 2) or a single-file deck (version 1).
    public static func decode(_ wrapper: FileWrapper) throws -> Deck {
        if wrapper.isDirectory {
            guard let deckData = wrapper.fileWrappers?[deckFileName]?.regularFileContents else {
                throw Error.notADeck
            }
            var deck = try decode(deckData)
            if let reviews = wrapper.fileWrappers?[reviewsFileName]?.regularFileContents {
                try ReviewLogEncoder.attach(reviews, to: &deck.cards)
            }
            return deck
        }
        guard let data = wrapper.regularFileContents else { throw Error.notADeck }
        return try decode(data)
    }

    /// Reads a single-file deck of version 1 (with review logs inside the cards) or
    /// the `deck.json` of a package (without them).
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

        let envelope = try decoder.decode(Envelope.self, from: data)
        return Deck(learningOptions: envelope.learningOptions, cards: envelope.cards, progress: envelope.progress)
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var learningOptions: LearningOptions
        var cards: [Card]
        var progress: [DailySnapshot]

        private enum CodingKeys: String, CodingKey {
            case format, version, cards
            case learningOptions = "settings"
            case progress = "history"
        }
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }
}

extension CodingUserInfoKey {
    /// When `true`, cards are encoded without their review log.
    static let omitReviewLog = CodingUserInfoKey(rawValue: "omitReviewLog")!
}
