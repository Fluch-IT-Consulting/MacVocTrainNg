import Foundation
import Testing

@testable import VocabCore

struct FSRSTests {
    let fsrs = FSRS()

    /// Reference values from `test_memo_state` in open-spaced-repetition/py-fsrs.
    @Test func memoryStateMatchesReferenceImplementation() {
        let grades: [Grade] = [.again, .good, .good, .good, .good, .good]
        let elapsed = [0, 0, 1, 3, 8, 21]
        var memory: FSRS.Memory?
        for (grade, days) in zip(grades, elapsed) {
            memory = fsrs.review(memory, elapsedDays: days, grade: grade)
        }
        #expect(abs(memory!.stability - 53.62691) < 1e-4)
        #expect(abs(memory!.difficulty - 6.3574867) < 1e-4)
    }

    @Test func retrievabilityIsNinetyPercentAfterStabilityDays() {
        #expect(abs(fsrs.retrievability(elapsedDays: 12.5, stability: 12.5) - 0.9) < 1e-12)
        #expect(fsrs.retrievability(elapsedDays: 0, stability: 3) == 1)
    }

    @Test func intervalEqualsStabilityAtNinetyPercentRetention() {
        #expect(abs(fsrs.interval(stability: 42, targetRecall: 0.9) - 42) < 1e-9)
        #expect(fsrs.interval(stability: 42, targetRecall: 0.95) < 42)
        #expect(fsrs.interval(stability: 42, targetRecall: 0.8) > 42)
    }

    @Test func initialStateUsesFirstFourWeights() {
        for grade in Grade.allCases {
            let memory = fsrs.review(nil, elapsedDays: 0, grade: grade)
            #expect(memory.stability == FSRSParameters.default[grade.rawValue - 1])
        }
        #expect(abs(fsrs.initialDifficulty(.again) - 6.4133) < 1e-9)
        #expect(fsrs.initialDifficulty(.easy) == 1)
    }

    @Test func forgettingReducesAndRecallIncreasesStability() {
        let memory = FSRS.Memory(stability: 10, difficulty: 5)
        #expect(fsrs.review(memory, elapsedDays: 10, grade: .again).stability < 10)
        let hard = fsrs.review(memory, elapsedDays: 10, grade: .hard).stability
        let good = fsrs.review(memory, elapsedDays: 10, grade: .good).stability
        let easy = fsrs.review(memory, elapsedDays: 10, grade: .easy).stability
        #expect(10 < hard && hard < good && good < easy)
    }

    @Test func sameDayRecallNeverLowersStability() {
        let memory = FSRS.Memory(stability: 30, difficulty: 5)
        #expect(fsrs.review(memory, elapsedDays: 0, grade: .good).stability >= 30)
        #expect(fsrs.review(memory, elapsedDays: 0, grade: .again).stability < 30)
    }

    @Test func parametersRejectInvalidWeights() throws {
        #expect(FSRSParameters([1, 2, 3]) == nil)
        #expect(FSRSParameters(FSRSParameters.default.weights) == FSRSParameters.default)
    }

    @Test func defaultParametersAreWithinTheirRanges() {
        #expect(FSRSParameters.default.indexOutOfRange == nil)
        var weights = FSRSParameters.default.weights
        weights[7] = 0.8
        #expect(FSRSParameters(weights)?.indexOutOfRange == 7)
    }
}
