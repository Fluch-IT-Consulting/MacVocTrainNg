import Foundation

/// Character-level comparison of a response with the answer, used to
/// highlight exactly what was wrong.
public enum ResponseDiff {
    public struct Segment: Hashable, Sendable {
        public var text: String
        /// `true` if this part of the answer was missing or mistyped.
        public var isMismatch: Bool
    }

    /// Splits `expected` into runs of characters that do or don't appear, in order,
    /// in `response` (longest common subsequence).
    public static func segments(response: String, expected: String) -> [Segment] {
        let a = Array(ResponseChecker.normalize(response))
        let b = Array(expected.precomposedStringWithCanonicalMapping)
        guard !b.isEmpty else { return [] }
        guard !a.isEmpty else { return [Segment(text: String(b), isMismatch: true)] }
        // Keep the quadratic table small; skip highlighting for pathological input.
        guard a.count <= 300, b.count <= 300 else { return [Segment(text: String(b), isMismatch: false)] }

        var lengths = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var matched = [Bool](repeating: false, count: b.count)
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                matched[j] = true
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }

        var segments: [Segment] = []
        for (character, isMatch) in zip(b, matched) {
            let mismatch = !isMatch && !character.isWhitespace
            if let last = segments.last, last.isMismatch == mismatch {
                segments[segments.count - 1].text.append(character)
            } else {
                segments.append(Segment(text: String(character), isMismatch: mismatch))
            }
        }
        return segments
    }
}
