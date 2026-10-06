import Foundation

/// Character-level comparison of a response with the answer, used to
/// highlight exactly what was wrong.
public enum ResponseDiff {
    public struct Segment: Hashable, Sendable {
        public var text: String
        /// `true` if this part of the answer was missing or mistyped.
        public var isMismatch: Bool
    }

    /// Splits `expected` into runs of characters that the response got right or not, aligned
    /// like the typo check (`Alignment`). Both characters of a swapped pair count as wrong;
    /// extra characters of the response have no place in the answer and mark nothing.
    public static func segments(response: String, expected: String) -> [Segment] {
        let a = Array(ResponseChecker.normalize(response))
        let b = Array(expected.precomposedStringWithCanonicalMapping)
        guard !b.isEmpty else { return [] }
        guard !a.isEmpty else { return [Segment(text: String(b), isMismatch: true)] }
        // Keep the quadratic table small; skip highlighting for pathological input.
        guard a.count <= 300, b.count <= 300 else { return [Segment(text: String(b), isMismatch: false)] }

        let operations = Alignment(response: a, expected: b).operations
        var segments: [Segment] = []
        for (character, operation) in zip(b, operations) {
            let mismatch = operation != .match && !character.isWhitespace
            if let last = segments.last, last.isMismatch == mismatch {
                segments[segments.count - 1].text.append(character)
            } else {
                segments.append(Segment(text: String(character), isMismatch: mismatch))
            }
        }
        return segments
    }
}
