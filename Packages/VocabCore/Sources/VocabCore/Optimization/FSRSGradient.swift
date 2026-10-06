import Foundation

/// Loss and gradient of the FSRS-6 model over training items, with the derivatives
/// worked out by hand. Port of `analytic.rs` in fsrs-rs 6.6.2.
///
/// The forward pass repeats the formulas of `FSRS` with the bounds of fsrs-rs (stability
/// also at most `maximumStability`) and records which branch each review took, so the
/// backward pass follows the same path. Gradients stop where a bound is exceeded.
struct FSRSGradient {
    static let maximumStability = 36500.0
    /// Predictions are clamped to `minimumProbability...(1 - minimumProbability)`
    /// before taking logarithms.
    static let minimumProbability = 1e-7

    private static let stabilityRange = FSRS.minimumStability...maximumStability

    let w: [Double]
    private let decay: Double
    private let factor: Double
    private let factorDerivative: Double
    private let failureFloorDivisor: Double
    private let easyDifficulty: Double

    init(weights: [Double]) {
        w = weights
        decay = -weights[20]
        let c = log(0.9)
        factor = exp(c / decay) - 1
        factorDerivative = exp(c / decay) * (-c / (decay * decay))
        failureFloorDivisor = exp(weights[17] * weights[18])
        easyDifficulty = Self.initialDifficulty(weights, grade: .easy)
    }

    /// Weighted binary cross-entropy summed over `items`; adds its gradient to `gradient`.
    func lossAndGradient(of items: ArraySlice<WeightedTrainingItem>, into gradient: inout [Double]) -> Double {
        var loss = 0.0
        var steps: [Step] = []
        for item in items {
            loss += lossAndGradient(of: item, steps: &steps, into: &gradient)
        }
        return loss
    }

    /// Stability before the target review of `item`, after replaying its history.
    func stability(before item: TrainingItem) -> Double {
        var state = State(s: 0, d: 0)
        for (n, review) in item.history.enumerated() {
            state = forward(state, review: review, n: n).state
        }
        return state.s
    }

    // MARK: - Forward

    private struct State {
        var s: Double
        var d: Double
    }

    private enum Branch {
        case initial, sameDay, lapse, recall
    }

    /// One review of the forward pass, as the backward pass needs it.
    private struct Step {
        var branch: Branch
        var grade: Grade
        var elapsedDays: Double
        /// The state before the review, as passed in and after clamping.
        var stateS: Double, stateD: Double
        var lastS: Double, lastD: Double
        var retrievability = 0.0
        var lapseRaw = 0.0
        var lapseFloor = 0.0
        var lapseUsedFloor = false
        var sameDayRaw = 0.0
        var sameDayValue = 0.0
        var sameDayRawActive = false
        var preClampS: Double
        var preClampD: Double
    }

    private static func initialDifficulty(_ w: [Double], grade: Grade) -> Double {
        w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1
    }

    private func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(max(0, elapsedDays) / stability * factor + 1, decay)
    }

    private func forward(_ state: State, review: TrainingReview, n: Int) -> (state: State, step: Step) {
        let lastS = state.s.clamped(to: Self.stabilityRange)
        let lastD = state.d.clamped(to: FSRS.difficultyRange)
        let grade = review.grade
        let rating = Double(grade.rawValue)
        let elapsedDays = Double(review.elapsedDays)

        if n == 0 {
            let s = w[grade.rawValue - 1]
            let d = Self.initialDifficulty(w, grade: grade)
            let step = Step(
                branch: .initial, grade: grade, elapsedDays: elapsedDays,
                stateS: state.s, stateD: state.d, lastS: lastS, lastD: lastD,
                preClampS: s, preClampD: d
            )
            return (State(s: s.clamped(to: Self.stabilityRange), d: d.clamped(to: FSRS.difficultyRange)), step)
        }

        var step = Step(
            branch: .recall, grade: grade, elapsedDays: elapsedDays,
            stateS: state.s, stateD: state.d, lastS: lastS, lastD: lastD,
            preClampS: 0, preClampD: 0
        )
        let r = retrievability(elapsedDays: elapsedDays, stability: lastS)
        step.retrievability = r

        let newS: Double
        if elapsedDays == 0 {
            step.branch = .sameDay
            step.sameDayRaw = exp(w[17] * (rating - 3 + w[18])) * pow(lastS, -w[19])
            step.sameDayRawActive = !(grade.isRecall && step.sameDayRaw < 1)
            step.sameDayValue = grade.isRecall ? max(step.sameDayRaw, 1) : step.sameDayRaw
            newS = lastS * step.sameDayValue
        } else if grade == .again {
            step.branch = .lapse
            step.lapseRaw = w[11] * pow(lastD, -w[12]) * (pow(lastS + 1, w[13]) - 1) * exp((1 - r) * w[14])
            step.lapseFloor = lastS / failureFloorDivisor
            step.lapseUsedFloor = step.lapseFloor < step.lapseRaw
            newS = step.lapseUsedFloor ? step.lapseFloor : step.lapseRaw
        } else {
            let hardPenalty = grade == .hard ? w[15] : 1
            let easyBonus = grade == .easy ? w[16] : 1
            let increase = exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1 - r) * w[10]) - 1)
                * hardPenalty * easyBonus
            newS = lastS * (increase + 1)
        }

        let deltaD = -w[6] * (rating - 3)
        let nextD = lastD + (10 - lastD) * deltaD / 9
        let meanD = w[7] * (easyDifficulty - nextD) + nextD
        step.preClampS = newS
        step.preClampD = meanD
        return (State(s: newS.clamped(to: Self.stabilityRange), d: meanD.clamped(to: FSRS.difficultyRange)), step)
    }

    // MARK: - Backward

    private func lossAndGradient(of item: WeightedTrainingItem, steps: inout [Step], into g: inout [Double]) -> Double {
        steps.removeAll(keepingCapacity: true)
        var state = State(s: 0, d: 0)
        for (n, review) in item.item.history.enumerated() {
            let (next, step) = forward(state, review: review, n: n)
            state = next
            steps.append(step)
        }

        let t = max(0, Double(item.item.target.elapsedDays))
        let r = retrievability(elapsedDays: t, stability: state.s)
        let label = item.item.target.grade.isRecall ? 1.0 : 0
        let (loss, gR) = Self.crossEntropy(r, label: label, weight: item.weight)

        var gS = curveBackward(elapsedDays: t, stability: state.s, retrievability: r, gR: gR, into: &g)
        var gD = 0.0
        for step in steps.reversed() {
            (gS, gD) = backward(step, gS: gS, gD: gD, into: &g)
        }
        return loss
    }

    /// Weighted cross-entropy and its derivative with respect to `rawR`, which is zero
    /// where the clamp is active.
    private static func crossEntropy(_ rawR: Double, label: Double, weight: Double) -> (loss: Double, gradient: Double) {
        guard weight != 0 else { return (0, 0) }
        let r = rawR.clamped(to: minimumProbability...(1 - minimumProbability))
        let loss = -(label * log(r) + (1 - label) * log(1 - r)) * weight
        let gradient = -weight * (label / r - (1 - label) / (1 - r))
        return (loss, rawR > minimumProbability && rawR < 1 - minimumProbability ? gradient : 0)
    }

    /// Adds the gradient for w20 and returns the one for the stability.
    private func curveBackward(elapsedDays t: Double, stability s: Double, retrievability r: Double, gR: Double, into g: inout [Double]) -> Double {
        guard gR != 0 else { return 0 }
        let base = t / s * factor + 1
        let gS = gR * r * decay / base * (-t * factor / (s * s))
        let dRdDecay = r * (log(base) + decay / base * (t / s * factorDerivative))
        // decay = -w20
        g[20] -= gR * dRdDecay
        return gS
    }

    private func backward(_ step: Step, gS gOutS: Double, gD gOutD: Double, into g: inout [Double]) -> (Double, Double) {
        let gPreS = gOutS * Self.passes(step.preClampS, Self.stabilityRange)
        var gLastS = 0.0
        var gLastD = 0.0
        var gR = 0.0

        switch step.branch {
        case .initial:
            backwardInitial(step, gS: gPreS, gD: gOutD, into: &g)
        case .sameDay:
            gLastS += backwardSameDay(step, gS: gPreS, into: &g)
            gLastD += backwardDifficulty(step, gD: gOutD, into: &g)
        case .lapse:
            let (s, d, r) = backwardLapse(step, gS: gPreS, into: &g)
            gLastS += s
            gLastD += d + backwardDifficulty(step, gD: gOutD, into: &g)
            gR += r
        case .recall:
            let (s, d, r) = backwardRecall(step, gS: gPreS, into: &g)
            gLastS += s
            gLastD += d + backwardDifficulty(step, gD: gOutD, into: &g)
            gR += r
        }

        gLastS += curveBackward(elapsedDays: max(0, step.elapsedDays), stability: step.lastS, retrievability: step.retrievability, gR: gR, into: &g)
        return (
            gLastS * Self.passes(step.stateS, Self.stabilityRange),
            gLastD * Self.passes(step.stateD, FSRS.difficultyRange)
        )
    }

    /// Like the clamps of PyTorch and Burn: the gradient passes on the bounds and
    /// stops outside.
    private static func passes(_ x: Double, _ range: ClosedRange<Double>) -> Double {
        range.contains(x) ? 1 : 0
    }

    private func backwardInitial(_ step: Step, gS: Double, gD: Double, into g: inout [Double]) {
        let index = step.grade.rawValue - 1
        g[index] += gS
        let gRawD = gD * Self.passes(Self.initialDifficulty(w, grade: step.grade), FSRS.difficultyRange)
        if gRawD != 0 {
            let offset = Double(index)
            g[4] += gRawD
            g[5] += gRawD * -offset * exp(offset * w[5])
        }
    }

    private func backwardRecall(_ step: Step, gS: Double, into g: inout [Double]) -> (s: Double, d: Double, r: Double) {
        guard gS != 0 else { return (0, 0, 0) }
        let s = step.lastS
        let d = step.lastD
        let r = step.retrievability
        let a = exp(w[8])
        let b = 11 - d
        let c = pow(s, -w[9])
        let expE = exp((1 - r) * w[10])
        let e = expE - 1
        let hard = step.grade == .hard ? w[15] : 1
        let easy = step.grade == .easy ? w[16] : 1
        let increase = a * b * c * e * hard * easy
        let gIncrease = gS * s

        g[8] += gIncrease * increase
        g[9] += gIncrease * increase * -log(s)
        g[10] += gIncrease * a * b * c * hard * easy * ((1 - r) * expE)
        if step.grade == .hard {
            g[15] += gIncrease * a * b * c * e * easy
        }
        if step.grade == .easy {
            g[16] += gIncrease * a * b * c * e * hard
        }
        return (
            gS * (increase + 1) + gIncrease * increase * (-w[9] / s),
            -(gIncrease * a * c * e * hard * easy),
            gIncrease * a * b * c * hard * easy * (-w[10] * expE)
        )
    }

    private func backwardLapse(_ step: Step, gS: Double, into g: inout [Double]) -> (s: Double, d: Double, r: Double) {
        guard gS != 0 else { return (0, 0, 0) }
        let s = step.lastS
        let d = step.lastD
        let r = step.retrievability
        if step.lapseUsedFloor {
            let floor = step.lapseFloor
            g[17] += gS * floor * -w[18]
            g[18] += gS * floor * -w[17]
            return (gS * floor / s, 0, 0)
        }
        let raw = step.lapseRaw
        let base = s + 1
        let p = pow(base, w[13])
        let dPow = pow(d, -w[12])
        let er = exp((1 - r) * w[14])

        g[11] += gS * raw / w[11]
        g[12] += gS * raw * -log(d)
        g[13] += gS * w[11] * dPow * er * p * log(base)
        g[14] += gS * raw * (1 - r)
        return (
            gS * w[11] * dPow * er * w[13] * p / base,
            gS * raw * (-w[12] / d),
            gS * raw * -w[14]
        )
    }

    private func backwardSameDay(_ step: Step, gS: Double, into g: inout [Double]) -> Double {
        guard gS != 0 else { return 0 }
        let s = step.lastS
        var gLastS = gS * step.sameDayValue
        if step.sameDayRawActive {
            let gRaw = gS * s
            let raw = step.sameDayRaw
            g[17] += gRaw * raw * (Double(step.grade.rawValue) - 3 + w[18])
            g[18] += gRaw * raw * w[17]
            g[19] += gRaw * raw * -log(s)
            gLastS += gRaw * raw * (-w[19] / s)
        }
        return gLastS
    }

    private func backwardDifficulty(_ step: Step, gD: Double, into g: inout [Double]) -> Double {
        guard gD != 0 else { return 0 }
        let gMean = gD * Self.passes(step.preClampD, FSRS.difficultyRange)
        guard gMean != 0 else { return 0 }
        let ratingMinus3 = Double(step.grade.rawValue) - 3
        let lastD = step.lastD
        let deltaD = -w[6] * ratingMinus3
        let nextD = lastD + (10 - lastD) * deltaD / 9

        g[7] += gMean * (easyDifficulty - nextD)
        g[4] += gMean * w[7]
        g[5] += gMean * w[7] * -3 * exp(3 * w[5])

        let gNext = gMean * (1 - w[7])
        g[6] += gNext * (10 - lastD) * -ratingMinus3 / 9
        return gNext * (1 - deltaD / 9)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
