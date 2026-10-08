import Foundation

/// Character-level comparison of a response with the answer, used to
/// highlight exactly what was wrong.
public enum ResponseDiff {
    public struct Segment: Hashable, Sendable {
        public var text: String
        /// `true` if this part of the answer was missing or mistyped.
        public var isMismatch: Bool
    }

    /// Splits `expected` into runs of characters that the response got right or not.
    ///
    /// Like `ResponseChecker`, it compares alternative by alternative, in any order: each
    /// alternative of the answer is paired with the alternative of the response that is close
    /// to it and aligned like the typo check (`Alignment`). Both characters of a swapped pair
    /// count as wrong; extra characters of the response mark nothing. Separators, whitespace
    /// and alternatives the response has nothing for are never marked. Pass the
    /// `caseSensitive` of the `ResponseChecker` that checked the response: without it, a
    /// character typed only in another case is not marked. The segments keep the case of
    /// `expected` either way.
    public static func segments(response: String, expected: String, caseSensitive: Bool) -> [Segment] {
        let answer = Array(expected.precomposedStringWithCanonicalMapping)
        guard !answer.isEmpty else { return [] }
        let given = ResponseChecker.alternatives(of: response)
        // Keep the quadratic tables small; skip highlighting for pathological input.
        guard response.count <= 300, answer.count <= 300 else { return [Segment(text: String(answer), isMismatch: false)] }

        // Alternatives without surrounding whitespace; the slices keep their offsets into `answer`.
        let parts = answer.split(separator: ResponseChecker.separator)
            .map(trimmed)
            .filter { !$0.isEmpty }
        var mismatches = [Bool](repeating: false, count: answer.count)
        for (partIndex, givenIndex) in pairs(given, parts.map { ResponseChecker.normalize(String($0)) }, caseSensitive: caseSensitive) {
            let part = parts[partIndex]
            let operations = Alignment(response: Array(given[givenIndex]), expected: Array(part), caseSensitive: caseSensitive).operations
            for (offset, operation) in zip(part.indices, operations) {
                mismatches[offset] = operation != .match && !answer[offset].isWhitespace
            }
        }
        return segments(answer, mismatches: mismatches)
    }

    /// Pairs alternatives of the answer (keys) with alternatives of the response (values) that
    /// `ResponseChecker` accepts as close, closest pairs first; each alternative is used once.
    /// The distance minds case only if `caseSensitive`.
    static func pairs(_ given: [String], _ expected: [String], caseSensitive: Bool) -> [Int: Int] {
        var candidates: [(distance: Int, expected: Int, given: Int)] = []
        for (g, response) in given.enumerated() {
            for (e, answer) in expected.enumerated() where ResponseChecker.isClose(response, answer) {
                let alignment = Alignment(response: Array(response), expected: Array(answer), caseSensitive: caseSensitive)
                candidates.append((alignment.distance, e, g))
            }
        }
        candidates.sort { ($0.distance, $0.expected, $0.given) < ($1.distance, $1.expected, $1.given) }

        var pairs: [Int: Int] = [:]
        var usedGiven: Set<Int> = []
        for candidate in candidates where pairs[candidate.expected] == nil && !usedGiven.contains(candidate.given) {
            pairs[candidate.expected] = candidate.given
            usedGiven.insert(candidate.given)
        }
        return pairs
    }

    /// The slice without leading and trailing whitespace, keeping its indices.
    private static func trimmed(_ slice: ArraySlice<Character>) -> ArraySlice<Character> {
        var slice = slice
        while slice.first?.isWhitespace == true { slice.removeFirst() }
        while slice.last?.isWhitespace == true { slice.removeLast() }
        return slice
    }

    /// Joins neighbouring characters with the same flag into one segment.
    private static func segments(_ characters: [Character], mismatches: [Bool]) -> [Segment] {
        var segments: [Segment] = []
        for (character, mismatch) in zip(characters, mismatches) {
            if let last = segments.last, last.isMismatch == mismatch {
                segments[segments.count - 1].text.append(character)
            } else {
                segments.append(Segment(text: String(character), isMismatch: mismatch))
            }
        }
        return segments
    }
}
