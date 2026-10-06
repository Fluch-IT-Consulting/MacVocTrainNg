import Foundation

/// Compares a response with the answer of a card.
///
/// An answer may consist of several alternatives separated by `/`, e.g.
/// `"Haus / Gebäude"`. The order of alternatives does not matter. Whitespace
/// differences and Unicode composition (e.g. a precomposed "ą" versus "a" plus
/// a combining ogonek) are ignored; diacritics themselves are not.
public struct ResponseChecker: Sendable {
    public static let separator: Character = "/"

    public var caseSensitive: Bool

    public init(caseSensitive: Bool = true) {
        self.caseSensitive = caseSensitive
    }

    public func check(_ response: String, against expected: String) -> CheckResult {
        let givenParts = Self.alternatives(of: response)
        let expectedParts = Self.alternatives(of: expected)
        guard !givenParts.isEmpty, !expectedParts.isEmpty else { return .wrong }

        let givenKeys = Set(givenParts.map(key))
        let expectedKeys = Set(expectedParts.map(key))

        if givenKeys.isSubset(of: expectedKeys) {
            if givenKeys == expectedKeys { return .correct }
            let missing = expectedParts.filter { !givenKeys.contains(key($0)) }
            return .incomplete(missing: missing)
        }

        let isClose = givenParts.allSatisfy { part in
            expectedParts.contains { Self.isClose(part, $0) }
        }
        return isClose ? .almostCorrect : .wrong
    }

    /// Splits an answer into normalised, non-empty alternatives.
    public static func alternatives(of text: String) -> [String] {
        text.split(separator: separator)
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func key(_ text: String) -> String {
        caseSensitive ? text : text.lowercased()
    }

    /// True for a capitalisation difference or a small number of typos.
    static func isClose(_ response: String, _ expected: String) -> Bool {
        let response = response.lowercased()
        let expected = expected.lowercased()
        if response == expected { return true }
        let length = expected.count
        let tolerance = length < 4 ? 0 : (length < 8 ? 1 : 2)
        guard tolerance > 0, abs(response.count - length) <= tolerance else { return false }
        return editDistance(Array(response), Array(expected)) <= tolerance
    }

    /// Damerau–Levenshtein distance (optimal string alignment): swapped neighbours count as one typo.
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        Alignment(response: a, expected: b).distance
    }
}
