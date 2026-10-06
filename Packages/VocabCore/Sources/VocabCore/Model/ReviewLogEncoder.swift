import Foundation

/// Writes and reads `reviews.jsonl`, the review log of a deck package.
///
/// Each line is one review, grouped by card in deck order:
///
/// ```
/// {"card":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":1791216000,"grade":3}
/// ```
///
/// `date` is in whole seconds since 1970. The encoder keeps the encoded lines of
/// every card and on the next call only encodes what changed, so saving costs the
/// same however long the log gets. A card's lines are reused while its log has
/// the same length and last entry, and extended when entries were appended.
/// Logs only ever grow at the end or are replaced as a whole (reset, undo,
/// deletion), so this is enough to notice every change.
public final class ReviewLogEncoder: @unchecked Sendable {
    private struct Chunk {
        var count: Int
        var last: ReviewLogEntry?
        var data: Data
    }

    // Saving runs on a background thread; the lock guards the cache.
    private let lock = NSLock()
    private var chunks: [Card.ID: Chunk] = [:]
    private var encodedCardCount = 0

    public init() {}

    /// Cards whose lines were encoded or extended by the last call to `encode`.
    var lastEncodedCardCount: Int {
        lock.withLock { encodedCardCount }
    }

    public func encode(_ cards: [Card]) -> Data {
        lock.withLock {
            var result = Data()
            var newChunks: [Card.ID: Chunk] = [:]
            newChunks.reserveCapacity(chunks.count)
            var encoded = 0

            for card in cards where !card.log.isEmpty {
                var chunk: Chunk
                if let cached = chunks[card.id], cached.count == card.log.count, cached.last == card.log.last {
                    chunk = cached
                } else if let cached = chunks[card.id], cached.count < card.log.count, card.log[cached.count - 1] == cached.last {
                    chunk = cached
                    Self.appendLines(for: card, entries: card.log[cached.count...], to: &chunk.data)
                    encoded += 1
                } else {
                    chunk = Chunk(count: 0, last: nil, data: Data())
                    Self.appendLines(for: card, entries: card.log[...], to: &chunk.data)
                    encoded += 1
                }
                chunk.count = card.log.count
                chunk.last = card.log.last
                newChunks[card.id] = chunk
                result.append(chunk.data)
            }

            chunks = newChunks
            encodedCardCount = encoded
            return result
        }
    }

    private static func appendLines(for card: Card, entries: ArraySlice<ReviewLogEntry>, to data: inout Data) {
        // Formatted by hand: a UUID and integers need no escaping, and a JSONEncoder
        // per line would cost more than the rest of the save.
        let id = card.id.uuidString
        for entry in entries {
            let seconds = Int(entry.date.timeIntervalSince1970.rounded(.down))
            data.append(contentsOf: "{\"card\":\"\(id)\",\"date\":\(seconds),\"grade\":\(entry.grade.rawValue)}\n".utf8)
        }
    }

    private struct Line: Decodable {
        var card: UUID
        var date: Int
        var grade: Grade
    }

    /// Replaces the review logs of `cards` with the ones in `data`. Lines of cards
    /// that no longer exist are dropped.
    static func attach(_ data: Data, to cards: inout [Card]) throws {
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .enumerated()
            .filter { !$0.element.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\r") } }

        var logs: [Card.ID: [ReviewLogEntry]] = [:]
        let decoder = JSONDecoder()
        // One decoder call for the whole file is much faster than one per line.
        var array = Data("[".utf8)
        for (index, line) in lines.enumerated() {
            if index > 0 { array.append(UInt8(ascii: ",")) }
            array.append(contentsOf: line.element)
        }
        array.append(UInt8(ascii: "]"))

        let decoded: [Line]
        do {
            decoded = try decoder.decode([Line].self, from: array)
        } catch {
            // Find the culprit so the error can name it.
            for (number, line) in lines where (try? decoder.decode(Line.self, from: Data(line))) == nil {
                throw DeckFile.Error.damagedReviewLog(line: number + 1)
            }
            throw DeckFile.Error.damagedReviewLog(line: 0)
        }

        for line in decoded {
            logs[line.card, default: []].append(ReviewLogEntry(date: Date(timeIntervalSince1970: Double(line.date)), grade: line.grade))
        }
        for index in cards.indices {
            cards[index].log = logs[cards[index].id] ?? []
        }
    }
}
