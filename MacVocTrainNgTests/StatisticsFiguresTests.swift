import Foundation
import Testing
import VocabCore

@testable import MacVocTrain

@MainActor
struct StatisticsFiguresTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let now = ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")!

    private func reviewCard(_ question: String, dueIn days: Double, stability: Double = 10) -> Card {
        var card = Card(question: question, answer: "a")
        card.learningState = LearningState(
            phase: .review,
            stability: stability,
            difficulty: 5,
            lastReview: now.addingTimeInterval(-3 * 86400),
            due: now.addingTimeInterval(days * 86400)
        )
        return card
    }

    @Test func summaryFollowsCardsAndTime() {
        let figures = StatisticsFigures()
        var deck = Deck(cards: [Card(question: "dom", answer: "Haus"), reviewCard("kot", dueIn: 1)])
        #expect(figures.summary(of: deck, at: now, calendar: calendar) == DeckStatistics.summary(of: deck, at: now, calendar: calendar))
        // The new card is due right away.
        #expect(figures.summary(of: deck, at: now, calendar: calendar).dueNow == 1)

        let later = now.addingTimeInterval(2 * 86400)
        #expect(figures.summary(of: deck, at: later, calendar: calendar).dueNow == 2)

        deck = Deck(cards: deck.cards + [reviewCard("pies", dueIn: 3)])
        #expect(figures.summary(of: deck, at: later, calendar: calendar).total == 3)
        #expect(figures.summary(of: deck, at: later, calendar: calendar) == DeckStatistics.summary(of: deck, at: later, calendar: calendar))
    }

    @Test func summaryFollowsLearningOptions() {
        let figures = StatisticsFigures()
        var deck = Deck(cards: [reviewCard("kot", dueIn: 5)])
        let before = figures.summary(of: deck, at: now, calendar: calendar).averageRecallProbability

        deck.learningOptions.parameters = FSRSParameters(FSRSParameters.default.weights.enumerated().map { $0 == 20 ? $1 * 2 : $1 })!
        let after = figures.summary(of: deck, at: now, calendar: calendar).averageRecallProbability
        #expect(after == DeckStatistics.summary(of: deck, at: now, calendar: calendar).averageRecallProbability)
        #expect(after != before)
    }

    @Test func timeIsReadOncePerTick() {
        let figures = StatisticsFigures()
        let clock = ManualClock(now)
        #expect(figures.time(forTick: now, from: clock.studyClock) == now)

        // Until the next tick, the summary keeps its time and stays in the cache.
        clock.now = now.addingTimeInterval(30)
        #expect(figures.time(forTick: now, from: clock.studyClock) == now)

        let nextTick = now.addingTimeInterval(60)
        #expect(figures.time(forTick: nextTick, from: clock.studyClock) == clock.now)
    }

    @Test func forecastFollowsCardsAndDay() {
        let figures = StatisticsFigures()
        var cards = [reviewCard("kot", dueIn: 2)]
        let today = calendar.dayNumber(for: now)
        #expect(figures.forecast(of: cards, calendar: calendar, today: today, days: 5) == [0, 0, 1, 0, 0])
        #expect(figures.forecast(of: cards, calendar: calendar, today: today + 1, days: 5) == [0, 1, 0, 0, 0])

        cards.append(reviewCard("pies", dueIn: 4))
        #expect(figures.forecast(of: cards, calendar: calendar, today: today + 1, days: 5) == [0, 1, 0, 1, 0])
    }

    @Test func progressKeepsEachGranularity() {
        let figures = StatisticsFigures()
        let today = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        let snapshots = [
            DailySnapshot(day: today - 40, bins: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            DailySnapshot(day: today - 2, bins: [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ]
        let days = figures.progress(of: snapshots, today: today, granularity: .day, firstWeekday: 2)
        let months = figures.progress(of: snapshots, today: today, granularity: .month, firstWeekday: 2)
        #expect(days.points == DeckStatistics.progress(snapshots: snapshots, today: today, granularity: .day, firstWeekday: 2))
        #expect(months.points == DeckStatistics.progress(snapshots: snapshots, today: today, granularity: .month, firstWeekday: 2))
        #expect(figures.progress(of: snapshots, today: today, granularity: .day, firstWeekday: 2).points == days.points)

        var changed = snapshots
        changed[1].bins = [0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(figures.progress(of: changed, today: today, granularity: .day, firstWeekday: 2).points.last?.bins == changed[1].bins)
        #expect(figures.progress(of: changed, today: today + 1, granularity: .day, firstWeekday: 2).points.last?.day == today + 1)
    }

    @Test func progressSeriesIsReadyToDraw() {
        let today = CivilDate(year: 2026, month: 10, day: 6).dayNumber
        let series = ProgressSeries(
            points: DeckStatistics.progress(
                snapshots: [
                    DailySnapshot(day: today - 1, bins: [2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                    DailySnapshot(day: today, bins: [0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 1]),
                ],
                today: today,
                granularity: .day
            ))
        #expect(series.dates == [chartDate(forDay: today - 1), chartDate(forDay: today)])
        #expect(series.bars.count == 2 * MaturityCategory.allCases.count)
        #expect(series.bars.prefix(MaturityCategory.allCases.count).map(\.category) == MaturityCategory.allCases.reversed())
        let lastDay = series.bars.filter { $0.id.day == today }
        #expect(lastDay.first { $0.category == .young }?.count == 4)
        #expect(lastDay.first { $0.category == .mastered }?.count == 1)
        #expect(Set(series.bars.map(\.id)).count == series.bars.count)

        #expect(series.index(closestTo: series.dates[0].addingTimeInterval(3600)) == 0)
        #expect(series.index(closestTo: series.dates[1].addingTimeInterval(86400 * 30)) == 1)
        #expect(ProgressSeries(points: []).index(closestTo: now) == nil)
    }
}
