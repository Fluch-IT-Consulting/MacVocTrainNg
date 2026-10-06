/// How a response matches the answer of a card. It only suggests a grade.
public enum CheckResult: Hashable, Sendable {
    /// All alternatives given, nothing wrong.
    case correct
    /// Only some of the alternatives given, but none wrong.
    case incomplete(missing: [String])
    /// Close to the answer: one typo or a capitalisation slip.
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
