import Foundation

/// The 21 weights of the FSRS-6 model.
public struct FSRSParameters: Hashable, Sendable {
    public static let count = 21

    /// Default weights of FSRS-6, as published by open-spaced-repetition/py-fsrs.
    public static let `default` = FSRSParameters(unchecked: [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ])

    public let weights: [Double]

    public init?(_ weights: [Double]) {
        guard weights.count == Self.count, weights.allSatisfy(\.isFinite), weights[20] > 0 else { return nil }
        self.weights = weights
    }

    private init(unchecked weights: [Double]) {
        self.weights = weights
    }

    public subscript(index: Int) -> Double { weights[index] }
}

/// The FSRS-6 memory model: how stability and difficulty evolve with each review.
///
/// This is a faithful port of the formulas in open-spaced-repetition/py-fsrs.
/// It contains no scheduling policy (learning steps, due dates); see `Scheduler`.
public struct FSRS: Sendable {
    public static let minimumStability = 0.001
    public static let difficultyRange: ClosedRange<Double> = 1...10

    public let parameters: FSRSParameters
    public let decay: Double
    public let factor: Double

    public init(parameters: FSRSParameters = .default) {
        self.parameters = parameters
        decay = -parameters[20]
        factor = pow(0.9, 1 / decay) - 1
    }

    private var w: FSRSParameters { parameters }

    /// Probability of recalling a card `elapsedDays` after the last review.
    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + factor * max(0, elapsedDays) / stability, decay)
    }

    /// Days after which the recall probability falls to `targetRecall` (unrounded;
    /// FSRS calls it "desired retention").
    public func interval(stability: Double, targetRecall: Double) -> Double {
        stability / factor * (pow(targetRecall, 1 / decay) - 1)
    }

    public func initialStability(_ grade: Grade) -> Double {
        clampStability(w[grade.rawValue - 1])
    }

    public func initialDifficulty(_ grade: Grade, clamped: Bool = true) -> Double {
        let difficulty = w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1
        return clamped ? clampDifficulty(difficulty) : difficulty
    }

    public func nextDifficulty(_ difficulty: Double, grade: Grade) -> Double {
        let delta = -w[6] * Double(grade.rawValue - 3)
        let damped = difficulty + (10 - difficulty) * delta / 9
        let reverted = w[7] * initialDifficulty(.easy, clamped: false) + (1 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    /// Stability after a review on the same day as the previous one.
    public func shortTermStability(_ stability: Double, grade: Grade) -> Double {
        var increase = exp(w[17] * (Double(grade.rawValue) - 3 + w[18])) * pow(stability, -w[19])
        if grade.isRecall {
            increase = max(increase, 1)
        }
        return clampStability(stability * increase)
    }

    public func nextRecallStability(difficulty: Double, stability: Double, retrievability: Double, grade: Grade) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        return stability
            * (1 + exp(w[8])
                * (11 - difficulty)
                * pow(stability, -w[9])
                * (exp((1 - retrievability) * w[10]) - 1)
                * hardPenalty
                * easyBonus)
    }

    public func nextForgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let longTerm =
            w[11]
            * pow(difficulty, -w[12])
            * (pow(stability + 1, w[13]) - 1)
            * exp((1 - retrievability) * w[14])
        let shortTerm = stability / exp(w[17] * w[18])
        return min(longTerm, shortTerm)
    }

    public func nextStability(difficulty: Double, stability: Double, retrievability: Double, grade: Grade) -> Double {
        let next =
            grade.isRecall
            ? nextRecallStability(difficulty: difficulty, stability: stability, retrievability: retrievability, grade: grade)
            : nextForgetStability(difficulty: difficulty, stability: stability, retrievability: retrievability)
        return clampStability(next)
    }

    public struct Memory: Hashable, Sendable {
        public var stability: Double
        public var difficulty: Double

        public init(stability: Double, difficulty: Double) {
            self.stability = stability
            self.difficulty = difficulty
        }
    }

    /// Applies one review to a memory state.
    ///
    /// - Parameters:
    ///   - memory: State before the review, `nil` for a card never reviewed.
    ///   - elapsedDays: Whole days since the previous review; ignored for new cards.
    public func review(_ memory: Memory?, elapsedDays: Int, grade: Grade) -> Memory {
        guard let memory else {
            return Memory(stability: initialStability(grade), difficulty: initialDifficulty(grade))
        }
        let stability: Double
        if elapsedDays < 1 {
            stability = shortTermStability(memory.stability, grade: grade)
        } else {
            let r = retrievability(elapsedDays: Double(elapsedDays), stability: memory.stability)
            stability = nextStability(difficulty: memory.difficulty, stability: memory.stability, retrievability: r, grade: grade)
        }
        return Memory(stability: stability, difficulty: nextDifficulty(memory.difficulty, grade: grade))
    }

    private func clampStability(_ stability: Double) -> Double {
        max(stability, Self.minimumStability)
    }

    private func clampDifficulty(_ difficulty: Double) -> Double {
        min(max(difficulty, Self.difficultyRange.lowerBound), Self.difficultyRange.upperBound)
    }
}
