import Foundation

/// Compares a typed answer with the expected one.
///
/// An answer may consist of several alternatives separated by `/`, e.g.
/// `"Haus / Gebäude"`. The order of alternatives does not matter. Whitespace
/// differences and Unicode composition (e.g. a precomposed "ą" versus "a" plus
/// a combining ogonek) are ignored; diacritics themselves are not.
public struct AnswerChecker: Sendable {
    public enum Result: Hashable, Sendable {
        /// All alternatives given, nothing wrong.
        case correct
        /// Only some of the alternatives given, but none wrong.
        case incomplete(missing: [String])
        /// Close to the expected answer: a typo or a capitalisation slip.
        case almostCorrect
        case wrong

        /// The grade suggested to the learner for this result.
        public var suggestedGrade: Grade {
            switch self {
            case .correct: .good
            case .incomplete: .hard
            case .almostCorrect, .wrong: .again
            }
        }
    }

    public static let separator: Character = "/"

    public var caseSensitive: Bool

    public init(caseSensitive: Bool = true) {
        self.caseSensitive = caseSensitive
    }

    public func check(_ given: String, against expected: String) -> Result {
        let givenParts = Self.alternatives(of: given)
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
    static func isClose(_ given: String, _ expected: String) -> Bool {
        let given = given.lowercased()
        let expected = expected.lowercased()
        if given == expected { return true }
        let length = expected.count
        let tolerance = length < 4 ? 0 : (length < 8 ? 1 : 2)
        guard tolerance > 0, abs(given.count - length) <= tolerance else { return false }
        return editDistance(Array(given), Array(expected)) <= tolerance
    }

    /// Damerau–Levenshtein distance (optimal string alignment): swapped neighbours count as one typo.
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
