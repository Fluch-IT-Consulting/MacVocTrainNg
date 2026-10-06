import Foundation

/// Question, answer and hint of a card as entered, without surrounding whitespace.
///
/// Adding, editing and importing cards share the rule: question and answer must not
/// be empty, the hint may be.
public struct CardText: Hashable, Sendable {
    public let question: String
    public let answer: String
    public let hint: String

    /// `nil` if the question or the answer is empty after trimming.
    public init?(question: String, answer: String, hint: String = "") {
        let question = Self.trimmed(question)
        let answer = Self.trimmed(answer)
        guard !question.isEmpty, !answer.isEmpty else { return nil }
        self.question = question
        self.answer = answer
        self.hint = Self.trimmed(hint)
    }

    /// `text` without surrounding whitespace and line breaks.
    public static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two questions are the same if their keys are equal, that is if they only differ
    /// in case and surrounding whitespace.
    public static func key(forQuestion question: String) -> String {
        trimmed(question).folding(options: .caseInsensitive, locale: nil)
    }
}
