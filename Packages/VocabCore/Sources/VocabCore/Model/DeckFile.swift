import Foundation

/// Reading and writing decks as JSON documents.
///
/// The file is a pretty-printed JSON object with sorted keys, so it stays readable
/// and produces small diffs under version control:
///
/// ```json
/// { "format": "com.mfluch.voctrain.deck", "version": 1, "settings": {…}, "cards": […], "history": […] }
/// ```
public enum DeckFile {
    public static let format = "com.mfluch.voctrain.deck"
    public static let currentVersion = 1

    public enum Error: Swift.Error, Equatable {
        case notADeck
        case unsupportedVersion(Int)
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var settings: DeckSettings
        var cards: [Card]
        var history: [DailySnapshot]
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }

    public static func encode(_ deck: Deck) throws -> Data {
        let envelope = Envelope(
            format: format,
            version: currentVersion,
            settings: deck.settings,
            cards: deck.cards,
            history: deck.history
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

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
        return Deck(settings: envelope.settings, cards: envelope.cards, history: envelope.history)
    }
}
