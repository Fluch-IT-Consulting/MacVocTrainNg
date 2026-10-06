import Foundation
import Testing

@testable import VocabCore

struct StatisticsTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    func reviewCard(stability: Double, due: Date? = nil) -> Card {
        var card = Card(question: "q", answer: "a")
        card.learningState = LearningState(phase: .review, stability: stability, difficulty: 5, lastReview: now, due: due ?? now)
        return card
    }

    @Test func stabilityBinsDoubleInWidth() {
        #expect(StabilityBins.bin(forStability: 0.3) == 1)
        #expect(StabilityBins.bin(forStability: 1) == 2)
        #expect(StabilityBins.bin(forStability: 1.99) == 2)
        #expect(StabilityBins.bin(forStability: 2) == 3)
        #expect(StabilityBins.bin(forStability: 300) == 10)
        #expect(StabilityBins.bin(forStability: 100_000) == 11)
    }

    @Test func newAndLearningCardsHaveTheirOwnBins() {
        var learning = Card(question: "q", answer: "a")
        learning.learningState = LearningState(phase: .relearning, stability: 50, difficulty: 5, lastReview: now, due: now)
        #expect(StabilityBins.bin(for: Card(question: "q", answer: "a")) == 0)
        #expect(StabilityBins.bin(for: learning) == 1)
        #expect(StabilityBins.histogram(of: [learning, reviewCard(stability: 3)]) == [0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func categoriesGroupBins() {
        #expect(MaturityCategory(bin: 0) == .new)
        #expect(MaturityCategory(card: reviewCard(stability: 3)) == .shaky)
        #expect(MaturityCategory(card: reviewCard(stability: 10)) == .young)
        #expect(MaturityCategory(card: reviewCard(stability: 30)) == .maturing)
        #expect(MaturityCategory(card: reviewCard(stability: 100)) == .mature)
        #expect(MaturityCategory(card: reviewCard(stability: 1000)) == .mastered)
        let counts = MaturityCategory.counts(fromBins: [1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0])
        #expect(counts[.shaky] == 9)
        #expect(counts[.young] == 5)
    }

    @Test func dailyProgressRepeatsLastKnownState() {
        let day = CivilDate(year: 2026, month: 10, day: 1).dayNumber
        let snapshots = [
            DailySnapshot(day: day, bins: [1]),
            DailySnapshot(day: day + 3, bins: [4]),
        ]
        let points = DeckStatistics.progress(snapshots: snapshots, today: day + 4, granularity: .day)
        #expect(points.map(\.day) == Array(day...(day + 4)))
        #expect(points.map { $0.bins[0] } == [1, 1, 1, 4, 4])
    }

    @Test func weeklyProgressUsesWeekEnds() {
        // 2026-10-07 is a Wednesday; weeks start on Monday.
        let today = CivilDate(year: 2026, month: 10, day: 7).dayNumber
        let start = CivilDate(year: 2026, month: 9, day: 20).dayNumber
        let points = DeckStatistics.progress(snapshots: [DailySnapshot(day: start, bins: [1])], today: today, granularity: .week)
        #expect(points.map { CivilDate(dayNumber: $0.day).isoString } == ["2026-09-20", "2026-09-27", "2026-10-04", "2026-10-07"])
    }

    @Test func monthlyProgressUsesMonthEnds() {
        let today = CivilDate(year: 2026, month: 3, day: 15).dayNumber
        let start = CivilDate(year: 2025, month: 12, day: 24).dayNumber
        let points = DeckStatistics.progress(snapshots: [DailySnapshot(day: start, bins: [1])], today: today, granularity: .month)
        #expect(points.map { CivilDate(dayNumber: $0.day).isoString } == ["2025-12-31", "2026-01-31", "2026-02-28", "2026-03-15"])
    }

    @Test func forecastCountsOverdueCardsToday() {
        let today = calendar.dayNumber(for: now)
        let cards = [
            reviewCard(stability: 1, due: calendar.start(ofDay: today - 3)),
            reviewCard(stability: 1, due: calendar.start(ofDay: today + 2)),
            reviewCard(stability: 1, due: calendar.start(ofDay: today + 40)),
            Card(question: "new", answer: "card"),
        ]
        #expect(DeckStatistics.forecast(cards: cards, calendar: calendar, today: today, days: 5) == [1, 0, 1, 0, 0])
    }

    @Test func summaryCountsTodaysReviews() {
        var card = reviewCard(stability: 10, due: now.addingTimeInterval(86400))
        card.log = [
            ReviewLogEntry(date: now.addingTimeInterval(-3 * 86400), grade: .good),
            ReviewLogEntry(date: now.addingTimeInterval(-60), grade: .again),
            ReviewLogEntry(date: now, grade: .good),
        ]
        let deck = Deck(cards: [card, Card(question: "new", answer: "card")])
        let summary = DeckStatistics.summary(of: deck, at: now, calendar: calendar)
        #expect(summary.total == 2)
        #expect(summary.new == 1)
        #expect(summary.dueNow == 1)
        #expect(summary.reviewsToday == 2)
        #expect(summary.recalledToday == 1)
        #expect(summary.averageRecallProbability == 1)
    }

    @Test func summaryCountsRecallProbabilityInStudyDays() {
        var reviewedThisMorning = reviewCard(stability: 2)
        reviewedThisMorning.learningState?.lastReview = calendar.start(ofDay: calendar.dayNumber(for: now))
        var reviewedLastNight = reviewCard(stability: 2)
        reviewedLastNight.learningState?.lastReview = calendar.start(ofDay: calendar.dayNumber(for: now)).addingTimeInterval(-60)
        let summary = DeckStatistics.summary(of: Deck(cards: [reviewedThisMorning, reviewedLastNight]), at: now, calendar: calendar)
        let oneDay = FSRS().retrievability(elapsedDays: 1, stability: 2)
        #expect(summary.averageRecallProbability == (1 + oneDay) / 2)
    }

    @Test func historyKeepsOneSnapshotPerDay() {
        var deck = Deck(cards: [Card(question: "q", answer: "a")])
        deck.updateProgress(day: 100)
        deck.cards.append(Card(question: "q2", answer: "a2"))
        deck.updateProgress(day: 100)
        deck.updateProgress(day: 101)
        deck.updateProgress(day: 99)
        #expect(deck.progress.map(\.day) == [100, 101])
        #expect(deck.progress.map(\.total) == [2, 2])
    }
}

struct CalendarTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)

    @Test func civilDateRoundTrips() {
        for dayNumber in [-1000, -1, 0, 1, 365, 10_000, 20_731, 50_000] {
            #expect(CivilDate(dayNumber: dayNumber).dayNumber == dayNumber)
        }
        #expect(CivilDate(dayNumber: 0).isoString == "1970-01-01")
        #expect(CivilDate(isoString: "2024-02-29")?.dayNumber == CivilDate(year: 2024, month: 2, day: 29).dayNumber)
        #expect(CivilDate(isoString: "2024-13-01") == nil)
        #expect(CivilDate.weekday(ofDayNumber: 0) == 5)  // Thursday
    }

    @Test func studyDayStartsAtRolloverHour() {
        let start = calendar.start(ofDay: CivilDate(year: 2026, month: 10, day: 5).dayNumber)
        #expect(calendar.dayNumber(for: start) == CivilDate(year: 2026, month: 10, day: 5).dayNumber)
        #expect(calendar.dayNumber(for: start.addingTimeInterval(-1)) == CivilDate(year: 2026, month: 10, day: 4).dayNumber)
    }

    @Test(arguments: [("Europe/Berlin", 2026, 3, 29), ("Europe/Berlin", 2026, 10, 25), ("America/New_York", 2026, 3, 8)])
    func studyDayStartsAtRolloverOnDaylightSavingDays(zone: String, year: Int, month: Int, day: Int) {
        let calendar = StudyCalendar(timeZone: TimeZone(identifier: zone)!, rolloverHour: 4)
        let dayNumber = CivilDate(year: year, month: month, day: day).dayNumber
        let start = calendar.start(ofDay: dayNumber)
        #expect(calendar.dayNumber(for: start) == dayNumber)
        #expect(calendar.dayNumber(for: start.addingTimeInterval(-60)) == dayNumber - 1)
    }

    @Test func daylightSavingDoesNotShiftDays() {
        // Clocks go back on 2026-10-25 in Berlin.
        let before = calendar.start(ofDay: CivilDate(year: 2026, month: 10, day: 24).dayNumber)
        let after = calendar.start(ofDay: CivilDate(year: 2026, month: 10, day: 26).dayNumber)
        #expect(calendar.days(from: before, to: after) == 2)
        #expect(after.timeIntervalSince(before) == 2 * 86400 + 3600)
    }
}
