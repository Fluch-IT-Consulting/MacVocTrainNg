import Foundation
import Testing
@testable import VocabCore

struct SchedulerTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)
    /// 2026-10-05 18:00 in Berlin.
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    var scheduler: Scheduler {
        var settings = DeckSettings()
        settings.fuzzing = false
        settings.learningSteps = 2
        return Scheduler(settings: settings, calendar: calendar)
    }

    @Test func newCardStaysInLearningUntilEnoughCorrectAnswers() {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .good, at: now)
        #expect(card.memory?.phase == .learning)
        #expect(card.memory?.step == 1)
        #expect(card.memory?.due == now)

        card = scheduler.review(card, grade: .good, at: now.addingTimeInterval(60))
        #expect(card.memory?.phase == .review)
        #expect(card.memory?.reps == 2)
        #expect(card.log.map(\.grade) == [.good, .good])
    }

    @Test func graduatedCardIsDueAtStartOfStudyDay() throws {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .easy, at: now)
        let memory = try #require(card.memory)
        #expect(memory.phase == .review)
        let expectedDays = Int(scheduler.fsrs.interval(stability: memory.stability, desiredRetention: 0.9).rounded())
        #expect(memory.due == calendar.start(ofDay: calendar.dayNumber(for: now) + expectedDays))
        #expect(calendar.dayNumber(for: memory.due) - calendar.dayNumber(for: now) == expectedDays)
    }

    @Test func againRestartsAndHardKeepsLearningStep() {
        var card = Card(question: "dom", answer: "Haus")
        card = scheduler.review(card, grade: .good, at: now)
        card = scheduler.review(card, grade: .hard, at: now)
        #expect(card.memory?.step == 1)
        card = scheduler.review(card, grade: .again, at: now)
        #expect(card.memory?.step == 0)
        #expect(card.memory?.phase == .learning)
        #expect(card.memory?.lapses == 0)
    }

    @Test func forgettingAReviewCardStartsRelearning() {
        var card = Card(question: "dom", answer: "Haus")
        card.memory = MemoryState(phase: .review, stability: 20, difficulty: 5, lastReview: now.addingTimeInterval(-20 * 86400), due: now)
        card = scheduler.review(card, grade: .again, at: now)
        #expect(card.memory?.phase == .relearning)
        #expect(card.memory?.lapses == 1)
        #expect(card.memory?.due == now)
        #expect(card.memory!.stability < 20)
    }

    @Test func successfulReviewKeepsCardInReview() {
        var card = Card(question: "dom", answer: "Haus")
        card.memory = MemoryState(phase: .review, stability: 20, difficulty: 5, lastReview: now.addingTimeInterval(-20 * 86400), due: now)
        card = scheduler.review(card, grade: .hard, at: now)
        #expect(card.memory?.phase == .review)
        #expect(card.memory!.stability > 20)
        #expect(card.memory!.due > now)
    }

    @Test func intervalRespectsMaximum() {
        var settings = DeckSettings()
        settings.fuzzing = false
        settings.maximumInterval = 30
        var random = SeededRandom(seed: 1)
        #expect(Scheduler(settings: settings).intervalDays(stability: 500, using: &random) == 30)
        #expect(Scheduler(settings: settings).intervalDays(stability: 0.01, using: &random) == 1)
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
