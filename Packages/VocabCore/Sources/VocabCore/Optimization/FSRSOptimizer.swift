import Foundation

/// Computes FSRS parameters from the review logs of a deck. Port of
/// `compute_parameters` and `evaluate` in fsrs-rs 6.6.2; see ADR 0002.
public struct FSRSOptimizer: Sendable {
    /// Training items a deck needs before the app offers to compute parameters.
    public static let minimumReviewCount = 400

    public enum Error: Swift.Error, Equatable {
        /// No card was ever reviewed again on a later study day.
        case notEnoughData
        /// Training produced weights outside the model.
        case invalidResult
    }

    /// How well a set of parameters predicts the reviews of a deck. Lower is better.
    public struct Evaluation: Hashable, Sendable {
        /// Mean cross-entropy of the predicted recall probabilities.
        public var logLoss: Double
        /// Root mean square error between predicted and actual recall rates, over bins
        /// of similar reviews (RMSE(bins) in FSRS).
        public var rmse: Double
    }

    /// Hyperparameters, as in `TrainingConfig::default()` of fsrs-rs.
    struct Configuration: Sendable {
        var epochs = 5
        var batchSize = 512
        var seed: UInt64 = 2023
        var learningRate = 0.04
        var maximumReviews = 256
        var gamma = 1.0
    }

    let items: [TrainingItem]
    let relearningSteps: Int
    var configuration = Configuration()

    public init(cards: [Card], learningOptions: LearningOptions, calendar: StudyCalendar) {
        self.init(items: TrainingItem.items(from: cards, calendar: calendar), relearningSteps: learningOptions.steps)
    }

    init(items: [TrainingItem], relearningSteps: Int) {
        self.items = items
        self.relearningSteps = relearningSteps
    }

    /// Reviews the optimizer learns from: those on a later study day than the previous
    /// review of the same card, of cards with a complete review log.
    public var reviewCount: Int { items.count }

    // MARK: - Training

    /// Trains parameters on the reviews.
    ///
    /// With fewer than 64 usable reviews only the initial stabilities are fitted, with
    /// fewer than 8 the result is the default. Checks for cancellation between batches.
    ///
    /// - Parameter progress: Called after each batch with the fraction done.
    public func computeParameters(progress: (Double) -> Void = { _ in }) throws -> FSRSParameters {
        let (initializationSet, trainingSet) = Self.removingOutliers(items)
        let averageRecall = trainingSet.isEmpty ? 0 : Double(trainingSet.count { $0.target.grade.isRecall }) / Double(trainingSet.count)
        guard trainingSet.count >= 8 else { return .default }

        guard let initial = InitialStability.fit(initializationSet, averageRecall: averageRecall) else {
            throw Error.notEnoughData
        }
        let defaults = FSRSParameters.default.weights
        let initialWeights = initial.stabilities + defaults[4...]
        if trainingSet.count == initializationSet.count || trainingSet.count < 64 {
            return try Self.parameters(initialWeights)
        }

        let weighted = Self.recencyWeighted(trainingSet).filter { $0.item.reviews.count <= configuration.maximumReviews }
        var weights = try train(weighted, initialWeights: initialWeights, progress: progress)
        guard weights.allSatisfy(\.isFinite) else { throw Error.invalidResult }

        let trained = Dictionary(uniqueKeysWithValues: Grade.allCases.map { ($0, weights[$0.rawValue - 1]) })
        guard let stabilities = InitialStability.smoothAndFill(trained, counts: initial.counts) else {
            throw Error.notEnoughData
        }
        weights.replaceSubrange(0..<4, with: stabilities)
        return try Self.parameters(weights)
    }

    private static func parameters(_ weights: [Double]) throws -> FSRSParameters {
        guard let parameters = FSRSParameters(weights) else { throw Error.invalidResult }
        return parameters
    }

    /// Standard deviations of the weights across many learners; the L2 term pulls
    /// weights with a small spread harder towards their initial value.
    private static let spread: [Double] = [
        6.43, 9.66, 17.58, 27.85, 0.57, 0.28, 0.6, 0.12, 0.39, 0.18, 0.33, 0.3, 0.09, 0.16, 0.57, 0.25,
        1.03, 0.31, 0.32, 0.14, 0.27,
    ]

    private func train(_ items: [WeightedTrainingItem], initialWeights: [Double], progress: (Double) -> Void) throws -> [Double] {
        let total = items.count
        let batchSize = configuration.batchSize
        let sorted = items.enumerated()
            .sorted { ($0.element.item.reviews.count, $0.offset) < ($1.element.item.reviews.count, $1.offset) }
            .map(\.element)
        let batches = stride(from: 0, to: sorted.count, by: batchSize).map { sorted[$0..<min($0 + batchSize, sorted.count)] }

        var schedule = CosineAnnealing(steps: Double((total / batchSize + 1) * configuration.epochs), learningRate: configuration.learningRate)
        var adam = Adam()
        var random = SeededRandom(seed: configuration.seed)
        var weights = initialWeights

        for epoch in 0..<configuration.epochs {
            var processed = 0
            for index in Array(batches.indices).shuffled(using: &random) {
                try Task.checkCancellation()
                let batch = batches[index]
                let learningRate = schedule.step()
                var gradient = [Double](repeating: 0, count: FSRSParameters.count)
                _ = FSRSGradient(weights: weights).lossAndGradient(of: batch, into: &gradient)

                let scale = configuration.gamma * Double(batch.count) / Double(total)
                for i in gradient.indices {
                    gradient[i] += 2 * (weights[i] - initialWeights[i]) / (Self.spread[i] * Self.spread[i]) * scale
                }
                adam.step(&weights, gradient: gradient, learningRate: learningRate)
                clip(&weights)

                processed += batch.count
                progress((Double(epoch * total) + Double(processed)) / Double(configuration.epochs * total))
            }
        }
        return weights
    }

    /// Keeps each weight in the range of fsrs-rs (`parameter_clipper.rs`).
    private func clip(_ w: inout [Double]) {
        // With several relearning steps, a lapse followed by that many same-day reviews
        // must not end above the stability before the lapse.
        let sameDayCeiling = relearningSteps > 1
            ? min(2, sqrt(max(0.01, -(log(w[11]) + log(pow(2, w[13]) - 1) + w[14] * 0.3) / Double(relearningSteps))))
            : 2
        let s = FSRS.minimumStability...InitialStability.maximum
        let ranges: [ClosedRange<Double>] = [
            s, s, s, s,
            FSRS.difficultyRange,
            0.001...4, 0.001...4, 0.001...0.75, 0...4.5, 0...0.8, 0.001...3.5, 0.001...5, 0.001...0.25,
            0.001...0.9, 0...4, 0...1, 1...6,
            0...sameDayCeiling, 0...sameDayCeiling, 0.01...0.8, 0.1...0.8,
        ]
        for i in w.indices {
            w[i] = w[i].clamped(to: ranges[i])
        }
    }

    // MARK: - Data preparation

    /// Splits off the items for fitting the initial stabilities and drops outliers
    /// (`prepare_training_data` in fsrs-rs).
    ///
    /// Items are grouped by the grade of the first review and the days until the first
    /// review on a later study day. Per grade, the smallest groups are dropped until 5 %
    /// of the items (at least 20) are gone, as are groups with fewer than 6 items or more
    /// than 100 days (365 after Easy). Training items from dropped groups go as well.
    static func removingOutliers(_ items: [TrainingItem]) -> (initialization: [TrainingItem], training: [TrainingItem]) {
        var groups: [Grade: [Int: [Int]]] = [:]
        for (index, item) in items.enumerated() where item.longTermReviewCount == 1 {
            groups[item.reviews[0].grade, default: [:]][item.target.elapsedDays, default: []].append(index)
        }

        var removed: [Grade: Set<Int>] = [:]
        var kept: [Int] = []
        for grade in Grade.allCases {
            guard let byDays = groups[grade] else { continue }
            // Largest first, then the longer interval; dropped from the end.
            let subgroups = byDays.sorted { ($0.value.count, $0.key) > ($1.value.count, $1.key) }
            let total = subgroups.reduce(0) { $0 + $1.value.count }
            var removedCount = 0
            for (days, indices) in subgroups.reversed() {
                if removedCount + indices.count >= max(20, total / 20) {
                    if indices.count >= 6 && days <= (grade == .easy ? 365 : 100) {
                        kept += indices
                    } else {
                        removed[grade, default: []].insert(days)
                    }
                } else {
                    removedCount += indices.count
                    removed[grade, default: []].insert(days)
                }
            }
        }

        let training = items.filter { item in
            guard let first = item.firstLongTermReview else { return false }
            return removed[item.reviews[0].grade]?.contains(first.elapsedDays) != true
        }
        return (kept.sorted().map { items[$0] }, training)
    }

    /// Weights from 0.25 for the oldest to 1 for the newest item, rising with the cube.
    static func recencyWeighted(_ items: [TrainingItem]) -> [WeightedTrainingItem] {
        let length = max(Double(items.count) - 1, 1)
        return items.enumerated().map { index, item in
            WeightedTrainingItem(item: item, weight: 0.25 + 0.75 * pow(Double(index) / length, 3))
        }
    }

    // MARK: - Evaluation

    /// How well `parameters` predict all reviews; `nil` without reviews.
    public func evaluate(_ parameters: FSRSParameters) -> Evaluation? {
        guard !items.isEmpty else { return nil }
        let model = FSRSGradient(weights: parameters.weights)
        let fsrs = FSRS(parameters: parameters)
        let range = FSRSGradient.minimumProbability...(1 - FSRSGradient.minimumProbability)

        var loss = 0.0
        var weightSum = 0.0
        var bins: [Bin: (predicted: Double, actual: Double, count: Double, weight: Double)] = [:]
        for weighted in Self.recencyWeighted(items) {
            let item = weighted.item
            let predicted = fsrs.retrievability(elapsedDays: Double(item.target.elapsedDays), stability: model.stability(before: item))
            let actual = item.target.grade.isRecall ? 1.0 : 0
            let r = predicted.clamped(to: range)
            loss -= (actual * log(r) + (1 - actual) * log(1 - r)) * weighted.weight
            weightSum += weighted.weight

            var bin = bins[Bin(item), default: (0, 0, 0, 0)]
            bin.predicted += predicted
            bin.actual += actual
            bin.count += 1
            bin.weight += weighted.weight
            bins[Bin(item)] = bin
        }

        var squares = 0.0
        var binWeights = 0.0
        for bin in bins.values {
            let difference = bin.predicted / bin.count - bin.actual / bin.count
            squares += difference * difference * bin.weight
            binWeights += bin.weight
        }
        return Evaluation(logLoss: loss / weightSum, rmse: sqrt(squares / binWeights))
    }

    /// Groups reviews by interval, number of earlier long-term reviews and lapses on
    /// roughly logarithmic scales (`r_matrix_index` in fsrs-rs).
    private struct Bin: Hashable {
        var interval: Int
        var length: Int
        var lapses: Int

        init(_ item: TrainingItem) {
            func bin(_ x: Double, scale: Double, base: Double) -> Double {
                scale * pow(base, (log(x) / log(base)).rounded(.down))
            }
            interval = Int((bin(Double(item.target.elapsedDays), scale: 2.48, base: 3.62) * 100).rounded())
            length = Int(bin(Double(item.longTermReviewCount + 1), scale: 1.99, base: 1.89).rounded())
            let lapseCount = item.lapseCount
            lapses = lapseCount == 0 ? 0 : Int(bin(Double(lapseCount), scale: 1.65, base: 1.73).rounded())
        }
    }
}

struct WeightedTrainingItem: Sendable {
    var item: TrainingItem
    var weight: Double
}

/// Adam as in fsrs-rs 6.6.2: β = (0.9, 0.999), ε = 1e-8.
private struct Adam {
    private var m = [Double](repeating: 0, count: FSRSParameters.count)
    private var v = [Double](repeating: 0, count: FSRSParameters.count)
    private var t = 0.0

    mutating func step(_ weights: inout [Double], gradient: [Double], learningRate: Double) {
        let beta1 = 0.9
        let beta2 = 0.999
        t += 1
        let bias1 = 1 - pow(beta1, t)
        let bias2 = 1 - pow(beta2, t)
        for i in weights.indices {
            m[i] = beta1 * m[i] + (1 - beta1) * gradient[i]
            v[i] = beta2 * v[i] + (1 - beta2) * gradient[i] * gradient[i]
            weights[i] -= learningRate * (m[i] / bias1) / ((v[i] / bias2).squareRoot() + 1e-8)
        }
    }
}

/// Cosine annealing of the learning rate down to 0 over `steps`, in the recursive form
/// of PyTorch that fsrs-rs copies.
private struct CosineAnnealing {
    let steps: Double
    let initial: Double
    private var count = -1.0
    private var current: Double

    init(steps: Double, learningRate: Double) {
        self.steps = steps
        initial = learningRate
        current = learningRate
    }

    mutating func step() -> Double {
        count += 1
        if count == 0 {
            current = initial
        } else if (count - 1 - steps).truncatingRemainder(dividingBy: 2 * steps) == 0 {
            current = initial * (1 - cos(.pi / steps)) / 2
        } else {
            current *= (1 + cos(.pi * count / steps)) / (1 + cos(.pi * (count - 1) / steps))
        }
        return current
    }
}
