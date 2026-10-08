import Foundation

/// Finds cards by question, answer or hint, ignoring case and diacritics, so "dzien"
/// finds "dzień".
///
/// Folds the text of every card once, so each search is a plain substring test and
/// stays fast while typing. Build a new index when cards are added, removed or moved;
/// replace the entry of a card whose text changed.
public struct CardSearchIndex: Sendable {
    /// Folded text per card, in the order of the cards the index was built from.
    private var texts: [String]

    public init(cards: [Card]) {
        texts = cards.map(Self.text(of:))
    }

    /// Replaces the entry at `position` with `card`, e.g. after its text was edited.
    public mutating func replace(at position: Int, with card: Card) {
        texts[position] = Self.text(of: card)
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

    private static func text(of card: Card) -> String {
        // The separator keeps a query from matching across two fields.
        fold(card.question + "\u{1F}" + card.answer + "\u{1F}" + card.hint)
    }

    /// Case- and diacritic-insensitive, and canonically composed so a literal
    /// comparison finds every match.
    ///
    /// `.diacriticInsensitive` only drops marks that canonical decomposition splits
    /// off, so letters with a stroke and the ligatures go through `plainLetters`.
    private static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard folded.unicodeScalars.contains(where: { plainLetters[$0] != nil }) else {
            return folded.precomposedStringWithCanonicalMapping
        }
        var plain = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if let letters = plainLetters[scalar] {
                plain.append(contentsOf: letters.unicodeScalars)
            } else {
                plain.append(scalar)
            }
        }
        return String(plain).precomposedStringWithCanonicalMapping
    }

    /// Lowercase letters without a canonical decomposition and their plain spelling,
    /// as folding already turns "ß" into "ss". Folding has lowercased the text before.
    private static let plainLetters: [Unicode.Scalar: String] = [
        "ł": "l", "ø": "o", "đ": "d", "ħ": "h", "æ": "ae", "œ": "oe",
    ]
}
