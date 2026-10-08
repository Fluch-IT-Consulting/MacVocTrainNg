import Foundation
import Testing

@testable import VocabCore

struct SchedulerTests {
    let calendar = StudyCalendar.testing
    /// 2026-10-05 18:00 in Berlin.
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    var scheduler: Scheduler {
        var learningOptions = LearningOptions()
        learningOptions.fuzzing = false
        learningOptions.steps = 2
        return Scheduler(learningOptions: learningOptions, calendar: calendar)
    }

    @Test func newCardStaysInLearningUntilEnoughSteps() {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .good, at: now)
        #expect(card.learningState?.phase == .learning)
        #expect(card.learningState?.step == 1)
        #expect(card.learningState?.due == now)

        card = scheduler.review(card, grade: .good, at: now.addingTimeInterval(60))
        #expect(card.learningState?.phase == .review)
        #expect(card.learningState?.reviews == 2)
        #expect(card.log.map(\.grade) == [.good, .good])
    }

    @Test func cardInReviewPhaseIsDueAtStartOfStudyDay() throws {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .easy, at: now)
        let learningState = try #require(card.learningState)
        #expect(learningState.phase == .review)
        let expectedDays = Int(scheduler.fsrs.interval(stability: learningState.stability, targetRecall: 0.9).rounded())
        #expect(learningState.due == calendar.start(ofDay: calendar.dayNumber(for: now) + expectedDays))
        #expect(calendar.dayNumber(for: learningState.due) - calendar.dayNumber(for: now) == expectedDays)
    }

    func reviewed(_ grades: [(hours: Double, grade: Grade)], by scheduler: Scheduler) -> Card {
        grades.reduce(Card(question: "dom", answer: "Haus")) { card, review in
            scheduler.review(card, grade: review.grade, at: now.addingTimeInterval(review.hours * 3600))
        }
    }

    @Test func replayWithSameParametersKeepsMemory() throws {
        let card = reviewed([(0, .again), (0.1, .good), (0.2, .good), (30, .hard), (100, .again), (100.1, .good), (300, .easy)], by: scheduler)
        #expect(scheduler.replayingMemory(of: card) == card)
    }

    @Test func replayWithOtherParametersChangesOnlyMemory() throws {
        let card = reviewed([(0, .good), (0.1, .good), (50, .good)], by: scheduler)
        var other = scheduler
        other.learningOptions.parameters = SyntheticLearner.unusual
        let replayed = try #require(other.replayingMemory(of: card))
        let before = try #require(card.learningState)
        let after = try #require(replayed.learningState)
        #expect(after.stability != before.stability)
        #expect(replayed.log == card.log)
        #expect(after.due == before.due)
        #expect(after.phase == before.phase)
        #expect(after.reviews == before.reviews)
    }

    @Test func replaySkipsCardsWithIncompleteLog() {
        var card = reviewed([(0, .good), (0.1, .good)], by: scheduler)
        card.learningState?.reviews = 7
        #expect(scheduler.replayingMemory(of: card) == nil)
        #expect(scheduler.replayingMemory(of: Card(question: "dom", answer: "Haus")) == nil)
    }

    @Test func againRestartsAndHardKeepsLearningStep() {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .good, at: now)
        card = scheduler.review(card, grade: .hard, at: now)
        #expect(card.learningState?.step == 1)
        card = scheduler.review(card, grade: .again, at: now)
        #expect(card.learningState?.step == 0)
        #expect(card.learningState?.phase == .learning)
        #expect(card.learningState?.lapses == 0)
    }

    @Test func forgettingAReviewCardStartsRelearning() {
        var card = Card(question: "dom", answer: "Haus")
        card.learningState = LearningState(phase: .review, stability: 20, difficulty: 5, lastReview: now.addingTimeInterval(-20 * 86400), due: now)
        card = scheduler.review(card, grade: .again, at: now)
        #expect(card.learningState?.phase == .relearning)
        #expect(card.learningState?.lapses == 1)
        #expect(card.learningState?.due == now)
        #expect(card.learningState!.stability < 20)
    }

    @Test func successfulReviewKeepsCardInReview() {
        var card = Card(question: "dom", answer: "Haus")
        card.learningState = LearningState(phase: .review, stability: 20, difficulty: 5, lastReview: now.addingTimeInterval(-20 * 86400), due: now)
        card = scheduler.review(card, grade: .hard, at: now)
        #expect(card.learningState?.phase == .review)
        #expect(card.learningState!.stability > 20)
        #expect(card.learningState!.due > now)
    }

    @Test func recallProbabilityCountsWholeStudyDays() {
        let today = calendar.start(ofDay: calendar.dayNumber(for: now))
        func recallProbability(lastReview: Date) -> Double {
            let learningState = LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: lastReview, due: now)
            return scheduler.recallProbability(of: learningState, at: now)
        }
        // 04:00 today: the same study day, although 14 hours have passed.
        #expect(recallProbability(lastReview: today) == 1)
        // 03:59 today still belongs to yesterday's study day.
        let oneDay = scheduler.fsrs.retrievability(elapsedDays: 1, stability: 5)
        #expect(recallProbability(lastReview: today.addingTimeInterval(-60)) == oneDay)
        #expect(recallProbability(lastReview: now.addingTimeInterval(-3 * 86400)) == scheduler.fsrs.retrievability(elapsedDays: 3, stability: 5))
        // A last review after `now`, e.g. after changing the clock, counts as just reviewed.
        #expect(recallProbability(lastReview: now.addingTimeInterval(2 * 86400)) == 1)
    }

    @Test func intervalRespectsMaximum() {
        var learningOptions = LearningOptions()
        learningOptions.fuzzing = false
        learningOptions.maximumInterval = 30
        var random = SeededRandom(seed: 1)
        #expect(Scheduler(learningOptions: learningOptions, calendar: calendar).intervalDays(stability: 500, using: &random) == 30)
        #expect(Scheduler(learningOptions: learningOptions, calendar: calendar).intervalDays(stability: 0.01, using: &random) == 1)
    }

    @Test func intervalBeyondIntRangeIsTheMaximum() {
        var random = SeededRandom(seed: 1)
        #expect(scheduler.intervalDays(stability: 1e19, using: &random) == scheduler.learningOptions.maximumInterval)
        #expect(scheduler.intervalDays(stability: 1e300, using: &random) == scheduler.learningOptions.maximumInterval)
    }

    @Test(arguments: [3, 10, 50, 400])
    func fuzzStaysWithinPyFSRSRanges(interval: Int) {
        var random = SeededRandom(seed: 42)
        var seen = Set<Int>()
        for _ in 0..<500 {
            let fuzzed = Scheduler.fuzzed(interval: interval, maximum: 36500, using: &random)
            seen.insert(fuzzed)
            #expect(fuzzed >= 2)
            #expect(abs(fuzzed - interval) <= max(2, interval / 10 + 2))
        }
        #expect(seen.count > 1)
    }

    @Test func shortIntervalsAreNotFuzzed() {
        var random = SeededRandom(seed: 7)
        #expect(Scheduler.fuzzed(interval: 2, maximum: 100, using: &random) == 2)
    }
}

extension Scheduler {
    /// Reviews with a fixed random source; the tests here schedule without fuzzing.
    fileprivate func review(_ card: Card, grade: Grade, at now: Date) -> Card {
        var random = SeededRandom(seed: 0)
        return review(card, grade: grade, at: now, using: &random)
    }
}
