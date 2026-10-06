import Foundation

/// Finds cards by question, answer or hint, ignoring case and diacritics, so "dzien"
/// finds "dzień".
///
/// Folds the text of every card once, so each search is a plain substring test and
/// stays fast while typing. Build a new index when the cards change.
public struct CardSearchIndex: Sendable {
    /// Folded text per card, in the order of the cards the index was built from.
    private let texts: [String]

    public init(cards: [Card]) {
        // The separator keeps a query from matching across two fields.
        texts = cards.map { Self.fold($0.question + "\u{1F}" + $0.answer + "\u{1F}" + $0.remark) }
    }

    /// The positions among `positions` whose cards match `query`, in the given order.
    /// A blank query matches every card.
    public func filter(_ positions: [Int], by query: String) -> [Int] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return positions }
        return positions.filter { texts[$0].range(of: needle, options: .literal) != nil }
    }

    /// The positions of all cards matching `query`, in deck order.
    public func positions(matching query: String) -> [Int] {
        filter(Array(texts.indices), by: query)
    }

    /// Case- and diacritic-insensitive, and canonically composed so a literal
    /// comparison finds every match.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }
}
