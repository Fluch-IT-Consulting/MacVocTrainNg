import Foundation
import Testing
@testable import VocabCore

struct ResponseCheckerTests {
    let checker = ResponseChecker()

    @Test func exactResponseIsCorrect() {
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

    @Test func emptyOrSeparatorOnlyResponseIsWrong() {
        #expect(checker.check("", against: "Haus") == .wrong)
        #expect(checker.check(" / ", against: "Haus") == .wrong)
    }

    @Test func caseMattersOnlyWhenRequested() {
        #expect(checker.check("haus", against: "Haus") == .almostCorrect)
        #expect(ResponseChecker(caseSensitive: false).check("haus", against: "Haus") == .correct)
    }

    @Test func smallTyposAreAlmostCorrect() {
        #expect(checker.check("Hasu", against: "Haus") == .almostCorrect)
        #expect(checker.check("dzien dobry", against: "dzień dobry") == .almostCorrect)
        #expect(checker.check("Wohnung", against: "Haus") == .wrong)
        // No tolerance for very short words.
        #expect(checker.check("tak", against: "tam") == .wrong)
    }

    @Test func wrongAlternativeMakesResponseWrong() {
        #expect(checker.check("Haus / Auto", against: "Haus / Gebäude") == .wrong)
    }

    @Test func suggestedGrades() {
        #expect(ResponseChecker.Result.correct.suggestedGrade == .good)
        #expect(ResponseChecker.Result.incomplete(missing: []).suggestedGrade == .hard)
        #expect(ResponseChecker.Result.almostCorrect.suggestedGrade == .again)
        #expect(ResponseChecker.Result.wrong.suggestedGrade == .again)
    }

    @Test func editDistanceCountsTranspositionAsOne() {
        #expect(ResponseChecker.editDistance(Array("abcd"), Array("abdc")) == 1)
        #expect(ResponseChecker.editDistance(Array(""), Array("abc")) == 3)
        #expect(ResponseChecker.editDistance(Array("kitten"), Array("sitting")) == 3)
    }
}

struct ResponseDiffTests {
    @Test func marksMissingCharacters() {
        let segments = ResponseDiff.segments(response: "dzien", expected: "dzień")
        #expect(segments.map(\.text) == ["dzie", "ń"])
        #expect(segments.map(\.isMismatch) == [false, true])
    }

    @Test func emptyResponseMarksEverything() {
        #expect(ResponseDiff.segments(response: "", expected: "Haus") == [.init(text: "Haus", isMismatch: true)])
    }

    @Test func identicalResponseHasNoMismatch() {
        #expect(ResponseDiff.segments(response: "Haus", expected: "Haus") == [.init(text: "Haus", isMismatch: false)])
    }
}
