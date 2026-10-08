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
        #expect(ResponseChecker(caseSensitive: false).check("haus", against: "Haus / Gebäude") == .incomplete(missing: ["Gebäude"]))
    }

    @Test func whitespaceAndUnicodeCompositionAreIgnored() {
        let decomposed = "dzien\u{0301}  dobry"  // n + combining acute accent
        #expect(checker.check("  \(decomposed) ", against: "dzień dobry") == .correct)
        #expect(checker.check("dzień dobry", against: decomposed) == .correct)
    }

    @Test func emptyOrSeparatorOnlyResponseIsWrong() {
        #expect(checker.check("", against: "Haus") == .wrong)
        #expect(checker.check(" / ", against: "Haus") == .wrong)
        #expect(checker.check("/", against: "Haus / Gebäude") == .wrong)
    }

    @Test func separatorOnlyAnswerIsOneAlternative() {
        #expect(ResponseChecker.alternatives(of: " / ") == ["/"])
        #expect(ResponseChecker.alternatives(of: " ") == [])
        #expect(checker.check("/", against: "/") == .correct)
        #expect(checker.check("  /  ", against: "/") == .correct)
        #expect(checker.check("Haus", against: "/") == .wrong)
        #expect(checker.check("", against: "/") == .wrong)
        #expect(checker.check("/  /", against: "/ /") == .correct)
        #expect(checker.check("//", against: "/ /") == .wrong)
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

    /// No typo below 4 characters of the alternative, one from 4, two from 8: each
    /// length at a limit with the most typos allowed and with one more.
    @Test(
        arguments: [
            ("zub", "Zub", .almostCorrect), ("Zup", "Zub", .wrong),
            ("Blem", "Blim", .almostCorrect), ("Plem", "Blim", .wrong),
            ("Flomtor", "Flomtur", .almostCorrect), ("Flamtor", "Flomtur", .wrong),
            ("Quepsila", "Quapsilo", .almostCorrect), ("Quepsela", "Quapsilo", .wrong),
        ] as [(String, String, CheckResult)])
    func typoToleranceGrowsWithTheLength(response: String, answer: String, result: CheckResult) {
        #expect(checker.check(response, against: answer) == result)
    }

    @Test func wrongAlternativeMakesResponseWrong() {
        #expect(checker.check("Haus / Auto", against: "Haus / Gebäude") == .wrong)
    }

    @Test func suggestedGrades() {
        #expect(CheckResult.correct.suggestedGrade == .good)
        #expect(CheckResult.incomplete(missing: []).suggestedGrade == .hard)
        #expect(CheckResult.almostCorrect.suggestedGrade == .again)
        #expect(CheckResult.wrong.suggestedGrade == .again)
    }

    @Test func editDistanceCountsTranspositionAsOne() {
        #expect(ResponseChecker.editDistance(Array("abcd"), Array("abdc")) == 1)
        #expect(ResponseChecker.editDistance(Array(""), Array("abc")) == 3)
        #expect(ResponseChecker.editDistance(Array("kitten"), Array("sitting")) == 3)
    }
}

struct ResponseDiffTests {
    @Test func marksMissingCharacters() {
        let segments = ResponseDiff.segments(response: "dzien", expected: "dzień", caseSensitive: true)
        #expect(segments.map(\.text) == ["dzie", "ń"])
        #expect(segments.map(\.isMismatch) == [false, true])
    }

    @Test func emptyResponseMarksNothing() {
        #expect(ResponseDiff.segments(response: "", expected: "Haus / Gebäude", caseSensitive: true) == [.init(text: "Haus / Gebäude", isMismatch: false)])
    }

    @Test func identicalResponseHasNoMismatch() {
        #expect(ResponseDiff.segments(response: "Haus", expected: "Haus", caseSensitive: true) == [.init(text: "Haus", isMismatch: false)])
    }

    @Test(arguments: [
        ("uWmbel", ["Wu", "mbel"], [true, false]),
        ("Wubmel", ["Wu", "mb", "el"], [false, true, false]),
        ("Wumble", ["Wumb", "el"], [false, true]),
    ])
    func transpositionMarksBothCharacters(response: String, texts: [String], mismatches: [Bool]) {
        let segments = ResponseDiff.segments(response: response, expected: "Wumbel", caseSensitive: true)
        #expect(segments.map(\.text) == texts)
        #expect(segments.map(\.isMismatch) == mismatches)
    }

    @Test func extraCharacterMarksNothing() {
        #expect(ResponseDiff.segments(response: "Hauus", expected: "Haus", caseSensitive: true) == [.init(text: "Haus", isMismatch: false)])
    }

    @Test func substitutionMarksOnlyTheWrongCharacter() {
        let segments = ResponseDiff.segments(response: "haus", expected: "Haus", caseSensitive: true)
        #expect(segments.map(\.text) == ["H", "aus"])
        #expect(segments.map(\.isMismatch) == [true, false])
    }

    @Test func alternativesInAnyOrderMarkOnlyTheTypo() {
        let segments = ResponseDiff.segments(response: "Gebäude / Hasu", expected: "Haus / Gebäude", caseSensitive: true)
        #expect(segments.map(\.text) == ["Ha", "us", " / Gebäude"])
        #expect(segments.map(\.isMismatch) == [false, true, false])
    }

    @Test func alternativeWithoutResponseIsNotMarked() {
        let segments = ResponseDiff.segments(response: "Hasu", expected: "Haus / Gebäude", caseSensitive: true)
        #expect(segments.map(\.text) == ["Ha", "us", " / Gebäude"])
        #expect(segments.map(\.isMismatch) == [false, true, false])
    }

    @Test func eachAlternativeIsPairedOnce() {
        // "Hause" is close to both; the exact "Haus" claims "Haus", leaving "Hause" for "Hausen".
        #expect(ResponseDiff.pairs(["Hause", "Haus"], ["Haus", "Hausen"], caseSensitive: true) == [0: 1, 1: 0])
        #expect(ResponseDiff.pairs(["Auto"], ["Haus", "Gebäude"], caseSensitive: true) == [:])
    }

    @Test(arguments: [
        ("wumbl", ["Wumb", "e", "l"], [false, true, false]),
        ("wumbele", ["Wumbel"], [false]),
        ("WUBMEL", ["Wu", "mb", "el"], [false, true, false]),
    ])
    func withoutCaseSensitivityCaseMarksNothing(response: String, texts: [String], mismatches: [Bool]) {
        let segments = ResponseDiff.segments(response: response, expected: "Wumbel", caseSensitive: false)
        #expect(segments.map(\.text) == texts)
        #expect(segments.map(\.isMismatch) == mismatches)
    }

    @Test func withCaseSensitivityCaseIsMarked() {
        let segments = ResponseDiff.segments(response: "wumbl", expected: "Wumbel", caseSensitive: true)
        #expect(segments.map(\.text) == ["W", "umb", "e", "l"])
        #expect(segments.map(\.isMismatch) == [true, false, true, false])
    }

    @Test func pairingIgnoresCaseOnlyWithoutCaseSensitivity() {
        // Without case sensitivity "haus" is "Haus" exactly and claims it, leaving "Hause" for "Hausen".
        #expect(ResponseDiff.pairs(["Hause", "haus"], ["Haus", "Hausen"], caseSensitive: false) == [0: 1, 1: 0])
        #expect(ResponseDiff.pairs(["Hause", "haus"], ["Haus", "Hausen"], caseSensitive: true) == [0: 0])
    }
}
