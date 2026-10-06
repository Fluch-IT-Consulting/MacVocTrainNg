import Foundation

/// Damerau–Levenshtein alignment (optimal string alignment) of a response with the answer.
///
/// Both the typo tolerance of `ResponseChecker` and the highlighting of `ResponseDiff`
/// rest on the same table, so a swap of neighbours counts as one typo and is shown as one.
struct Alignment {
    /// What the response did with one character of the answer.
    enum Operation: Equatable {
        case match
        case substitution
        case omission
        /// Swapped with its neighbour; both characters carry this operation.
        case transposition
    }

    /// `table[i][j]` is the distance between the first `i` characters of the response
    /// and the first `j` characters of the answer.
    private let table: [[Int]]
    private let response: [Character]
    private let expected: [Character]

    init(response: [Character], expected: [Character]) {
        self.response = response
        self.expected = expected
        var table = [[Int]](repeating: [Int](repeating: 0, count: expected.count + 1), count: response.count + 1)
        for i in 0...response.count { table[i][0] = i }
        for j in 0...expected.count { table[0][j] = j }
        for i in response.indices {
            for j in expected.indices {
                let cost = response[i] == expected[j] ? 0 : 1
                table[i + 1][j + 1] = min(table[i][j + 1] + 1, table[i + 1][j] + 1, table[i][j] + cost)
                if isTransposition(i + 1, j + 1, response, expected) {
                    table[i + 1][j + 1] = min(table[i + 1][j + 1], table[i - 1][j - 1] + 1)
                }
            }
        }
        self.table = table
    }

    var distance: Int { table[response.count][expected.count] }

    /// One operation per character of the answer. Extra characters of the response have no
    /// place in the answer and don't appear. On a tie the trace prefers a match, then a
    /// transposition, a substitution, an omission and finally an extra character.
    var operations: [Operation] {
        var operations = [Operation](repeating: .match, count: expected.count)
        var i = response.count
        var j = expected.count
        while j > 0 {
            let cell = table[i][j]
            if i > 0, response[i - 1] == expected[j - 1], cell == table[i - 1][j - 1] {
                i -= 1
                j -= 1
            } else if isTransposition(i, j, response, expected), cell == table[i - 2][j - 2] + 1 {
                operations[j - 1] = .transposition
                operations[j - 2] = .transposition
                i -= 2
                j -= 2
            } else if i > 0, cell == table[i - 1][j - 1] + 1 {
                operations[j - 1] = .substitution
                i -= 1
                j -= 1
            } else if cell == table[i][j - 1] + 1 {
                operations[j - 1] = .omission
                j -= 1
            } else {
                i -= 1
            }
        }
        return operations
    }
}

/// True if the last two of the first `i` response characters are the last two of the
/// first `j` answer characters, swapped.
private func isTransposition(_ i: Int, _ j: Int, _ response: [Character], _ expected: [Character]) -> Bool {
    i > 1 && j > 1 && response[i - 1] == expected[j - 2] && response[i - 2] == expected[j - 1]
}
