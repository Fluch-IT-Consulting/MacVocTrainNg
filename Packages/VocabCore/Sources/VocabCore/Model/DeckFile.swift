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
/// diffs well. The review log lives apart because it grows with every review: kept
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
        return try encoder.encode(envelope)
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

        let envelope = try decoder.decode(Envelope.self, from: data)
        return Deck(learningOptions: envelope.learningOptions, cards: envelope.cards, progress: envelope.progress)
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var learningOptions: LearningOptions
        var cards: [Card]
        var progress: [DailySnapshot]
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }
}
