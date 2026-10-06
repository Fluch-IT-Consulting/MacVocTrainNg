import Foundation
import Testing

@testable import VocabCore

struct OptimizerTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "UTC")!)

    func items(_ histories: [SyntheticLearner.History]) -> [TrainingItem] {
        TrainingItem.items(from: histories.enumerated().map { $1.card(index: $0, calendar: calendar) }, calendar: calendar)
    }

    func syntheticItems(cards: Int, seed: UInt64) -> [TrainingItem] {
        var learner = SyntheticLearner(parameters: SyntheticLearner.unusual, seed: seed)
        return items(learner.histories(cards: cards, days: 365))
    }

    // MARK: - Training items

    @Test func itemsCoverReviewsOnLaterStudyDays() throws {
        let start = calendar.start(ofDay: 20_000)
        let log: [(TimeInterval, Grade)] = [
            (0, .again), (600, .good), (86400, .good), (3 * 86400, .again), (3 * 86400 + 600, .good),
        ]
        let card = Card(
            question: "q", answer: "a",
            learningState: LearningState(phase: .review, stability: 1, difficulty: 5, lastReview: start, due: start, reviews: log.count),
            log: log.map { ReviewLogEntry(date: start.addingTimeInterval($0), grade: $1) }
        )

        let items = TrainingItem.items(from: [card], calendar: calendar)
        #expect(items.map(\.reviews.count) == [3, 4])
        #expect(items[1].reviews.map(\.elapsedDays) == [0, 0, 1, 2])
        #expect(items[1].reviews.map(\.grade) == [.again, .good, .good, .again])
        #expect(items[1].history.count == 3)
    }

    @Test func itemsSkipCardsWithIncompleteLog() {
        let start = calendar.start(ofDay: 20_000)
        let log = [ReviewLogEntry(date: start, grade: .good), ReviewLogEntry(date: start.addingTimeInterval(86400), grade: .good)]
        var imported = Card(question: "q", answer: "a", learningState: LearningState(phase: .review, stability: 3, difficulty: 5, lastReview: start, due: start, reviews: 5), log: log)
        #expect(!imported.hasCompleteLog)
        #expect(TrainingItem.items(from: [imported], calendar: calendar).isEmpty)
        imported.learningState?.reviews = 2
        #expect(TrainingItem.items(from: [imported], calendar: calendar).count == 1)
    }

    @Test func itemsAreOrderedByTimeOfTheirReview() {
        let start = calendar.start(ofDay: 20_000)
        func card(firstDay: Int, secondDay: Int) -> Card {
            let log = [firstDay, secondDay].map { ReviewLogEntry(date: start.addingTimeInterval(Double($0) * 86400), grade: .good) }
            return Card(question: "q", answer: "a", learningState: LearningState(phase: .review, stability: 1, difficulty: 5, lastReview: start, due: start, reviews: 2), log: log)
        }
        let items = TrainingItem.items(from: [card(firstDay: 0, secondDay: 9), card(firstDay: 0, secondDay: 4)], calendar: calendar)
        #expect(items.map(\.target.elapsedDays) == [4, 9])
    }

    // MARK: - Model and gradient

    @Test func forwardPassMatchesTheModel() {
        let parameters = SyntheticLearner.unusual
        let gradient = FSRSGradient(weights: parameters.weights)
        let fsrs = FSRS(parameters: parameters)
        for item in syntheticItems(cards: 40, seed: 1) {
            var memory: FSRS.Memory?
            for review in item.history {
                memory = fsrs.review(memory, elapsedDays: review.elapsedDays, grade: review.grade)
            }
            #expect(abs(gradient.stability(before: item) - memory!.stability) <= 1e-9 * memory!.stability)
        }
    }

    @Test func gradientMatchesFiniteDifferences() {
        let items = FSRSOptimizer.recencyWeighted(syntheticItems(cards: 40, seed: 2))[...]
        var weights = SyntheticLearner.unusual.weights
        weights[7] = 0.05  // away from its lower bound
        var analytic = [Double](repeating: 0, count: FSRSParameters.count)
        _ = FSRSGradient(weights: weights).lossAndGradient(of: items, into: &analytic)

        func loss(_ weights: [Double]) -> Double {
            var ignored = [Double](repeating: 0, count: FSRSParameters.count)
            return FSRSGradient(weights: weights).lossAndGradient(of: items, into: &ignored)
        }
        for i in weights.indices {
            let h = 1e-6 * max(1, abs(weights[i]))
            var up = weights
            var down = weights
            up[i] += h
            down[i] -= h
            let numeric = (loss(up) - loss(down)) / (2 * h)
            #expect(abs(numeric - analytic[i]) <= 1e-4 * max(1, abs(numeric)), "w\(i): \(numeric) vs \(analytic[i])")
        }
    }

    // MARK: - Initial stability

    @Test func initialStabilityFromOneGradeScalesTheDefaults() throws {
        let stabilities = try #require(InitialStability.smoothAndFill([.good: 4.6130], counts: [.good: 10]))
        let factor = 4.6130 / FSRSParameters.default[2]
        for (value, defaultValue) in zip(stabilities, FSRSParameters.default.weights) {
            #expect(abs(value - defaultValue * factor) < 1e-9)
        }
    }

    @Test func initialStabilitiesGrowWithTheGrade() throws {
        let stabilities = try #require(
            InitialStability.smoothAndFill(
                [.again: 3, .hard: 2, .good: 5, .easy: 20],
                counts: [.again: 50, .hard: 10, .good: 100, .easy: 20]
            ))
        // Again has more data than Hard, so Hard moves up to Again.
        #expect(stabilities == [3, 3, 5, 20])
        #expect(InitialStability.smoothAndFill([:], counts: [:]) == nil)
    }

    // MARK: - Training

    @Test func fewReviewsGiveDefaultsOrOnlyInitialStabilities() throws {
        func item(_ second: Grade) -> TrainingItem {
            TrainingItem(reviews: [TrainingReview(grade: .good, elapsedDays: 0), TrainingReview(grade: second, elapsedDays: 3)])
        }
        let few = Array(repeating: item(.good), count: 5)
        #expect(try FSRSOptimizer(items: few, relearningSteps: 2).computeParameters() == .default)

        // Too few to train, enough to fit the initial stabilities.
        let some = Array(repeating: item(.good), count: 30) + Array(repeating: item(.again), count: 10)
        let parameters = try FSRSOptimizer(items: some, relearningSteps: 2).computeParameters()
        #expect(parameters.weights[4...] == FSRSParameters.default.weights[4...])
        #expect(parameters[2] != FSRSParameters.default[2])
    }

    @Test func trainingImprovesPredictions() throws {
        let optimizer = FSRSOptimizer(items: syntheticItems(cards: 600, seed: 4), relearningSteps: 2)
        var reported: [Double] = []
        let parameters = try optimizer.computeParameters { reported.append($0) }

        let before = try #require(optimizer.evaluate(.default))
        let after = try #require(optimizer.evaluate(parameters))
        #expect(after.logLoss < before.logLoss)
        #expect(after.rmse < before.rmse)
        #expect(reported == reported.sorted())
        #expect(reported.last == 1)
    }

    @Test func trainingCanBeCancelled() async throws {
        let optimizer = FSRSOptimizer(items: syntheticItems(cards: 300, seed: 5), relearningSteps: 2)
        let task = Task { try optimizer.computeParameters() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: - Comparison with fsrs-rs

    struct Reference: Decodable {
        struct Evaluation: Decodable {
            var logLoss: Double
            var rmse: Double
        }
        var itemCount: Int
        var defaultEvaluation: Evaluation
        var parameters: [Double]
        var evaluation: Evaluation
        var singleBatchParameters: [Double]
    }

    /// Review histories of `SyntheticLearner` and what fsrs-rs 6.6.2 computes for them,
    /// written by `Tools/fsrs-reference`.
    func reference() throws -> (optimizer: FSRSOptimizer, reference: Reference) {
        func load(_ name: String) throws -> Data {
            let url = try #require(Bundle.module.url(forResource: "Resources/\(name)", withExtension: "json"))
            return try Data(contentsOf: url)
        }
        let histories = try JSONDecoder().decode([SyntheticLearner.History].self, from: load("fsrs-reference-histories"))
        let reference = try JSONDecoder().decode(Reference.self, from: load("fsrs-reference-results"))
        return (FSRSOptimizer(items: items(histories), relearningSteps: 2), reference)
    }

    @Test func evaluationMatchesFSRSRS() throws {
        let (optimizer, reference) = try reference()
        #expect(optimizer.reviewCount == reference.itemCount)
        for (parameters, expected) in [(FSRSParameters.default.weights, reference.defaultEvaluation), (reference.parameters, reference.evaluation)] {
            let parameters = try #require(FSRSParameters(parameters))
            let evaluation = try #require(optimizer.evaluate(parameters))
            #expect(abs(evaluation.logLoss - expected.logLoss) < 1e-5)
            #expect(abs(evaluation.rmse - expected.rmse) < 1e-5)
        }
    }

    @Test func singleBatchTrainingMatchesFSRSRS() throws {
        var (optimizer, reference) = try reference()
        optimizer.configuration.batchSize = reference.itemCount + 1
        let parameters = try optimizer.computeParameters()
        for (i, (actual, expected)) in zip(parameters.weights, reference.singleBatchParameters).enumerated() {
            #expect(abs(actual - expected) <= 1e-3 * max(1, abs(expected)), "w\(i): \(actual) vs \(expected)")
        }
    }

    /// With several batches the order differs from fsrs-rs, so the weights do as well;
    /// the predictions must be as good.
    @Test func trainingPredictsAsWellAsFSRSRS() throws {
        let (optimizer, reference) = try reference()
        let parameters = try optimizer.computeParameters()
        let evaluation = try #require(optimizer.evaluate(parameters))
        #expect(evaluation.logLoss <= reference.evaluation.logLoss * 1.002)
        #expect(evaluation.logLoss < reference.defaultEvaluation.logLoss)
    }
}
