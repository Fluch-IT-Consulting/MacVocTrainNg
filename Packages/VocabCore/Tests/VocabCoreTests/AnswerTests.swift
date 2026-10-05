import Foundation
import Testing
@testable import VocabCore

struct AnswerCheckerTests {
    let checker = AnswerChecker()

    @Test func exactAnswerIsCorrect() {
        #expect(checker.check("Haus", against: "Haus") == .correct)
    }

    @Test func alternativesInAnyOrderAreCorrect() {
        #expect(checker.check("Gebäude / Haus", against: "Haus/Gebäude") == .correct)
    }

    @Test func someAlternativesAreIncomplete() {
        #expect(checker.check("Haus", against: "Haus / Gebäude") == .incomplete(missing: ["Gebäude"]))
    }

    @Test func whitespaceAndUnicodeCompositionAreIgnored() {
        let decomposed = "dzien\u{0301}  dobry" // n + combining acute accent
        #expect(checker.check("  \(decomposed) ", against: "dzień dobry") == .correct)
    }

    @Test func emptyOrSeparatorOnlyAnswerIsWrong() {
        #expect(checker.check("", against: "Haus") == .wrong)
        #expect(checker.check(" / ", against: "Haus") == .wrong)
    }

    @Test func caseMattersOnlyWhenRequested() {
        #expect(checker.check("haus", against: "Haus") == .almostCorrect)
        #expect(AnswerChecker(caseSensitive: false).check("haus", against: "Haus") == .correct)
    }

    @Test func smallTyposAreAlmostCorrect() {
        #expect(checker.check("Hasu", against: "Haus") == .almostCorrect)
        #expect(checker.check("dzien dobry", against: "dzień dobry") == .almostCorrect)
        #expect(checker.check("Wohnung", against: "Haus") == .wrong)
        // No tolerance for very short words.
        #expect(checker.check("tak", against: "tam") == .wrong)
    }

    @Test func wrongAlternativeMakesAnswerWrong() {
        #expect(checker.check("Haus / Auto", against: "Haus / Gebäude") == .wrong)
    }

    @Test func suggestedGrades() {
        #expect(AnswerChecker.Result.correct.suggestedGrade == .good)
        #expect(AnswerChecker.Result.incomplete(missing: []).suggestedGrade == .hard)
        #expect(AnswerChecker.Result.almostCorrect.suggestedGrade == .again)
        #expect(AnswerChecker.Result.wrong.suggestedGrade == .again)
    }

    @Test func editDistanceCountsTranspositionAsOne() {
        #expect(AnswerChecker.editDistance(Array("abcd"), Array("abdc")) == 1)
        #expect(AnswerChecker.editDistance(Array(""), Array("abc")) == 3)
        #expect(AnswerChecker.editDistance(Array("kitten"), Array("sitting")) == 3)
    }
}

struct AnswerDiffTests {
    @Test func marksMissingCharacters() {
        let segments = AnswerDiff.segments(given: "dzien", expected: "dzień")
        #expect(segments.map(\.text) == ["dzie", "ń"])
        #expect(segments.map(\.isMismatch) == [false, true])
    }

    @Test func emptyAnswerMarksEverything() {
        #expect(AnswerDiff.segments(given: "", expected: "Haus") == [.init(text: "Haus", isMismatch: true)])
    }

    @Test func identicalAnswerHasNoMismatch() {
        #expect(AnswerDiff.segments(given: "Haus", expected: "Haus") == [.init(text: "Haus", isMismatch: false)])
    }
}
