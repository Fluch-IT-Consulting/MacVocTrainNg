import Foundation
import VocabCore

/// Converts a study day to a date for the chart axis (noon avoids time zone edges).
func chartDate(forDay day: Int) -> Date {
    let civil = CivilDate(dayNumber: day)
    return Calendar.current.date(from: DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: 12)) ?? Date()
}

/// The progress of a deck, prepared for the chart.
struct ProgressSeries {
    /// One stacked segment of the chart.
    struct Bar: Identifiable {
        struct ID: Hashable {
            var day: Int
            var category: MaturityCategory
        }

        var id: ID
        var date: Date
        var category: MaturityCategory
        var count: Int
    }

    var points: [DeckStatistics.ProgressPoint]
    /// The chart date of each point.
    var dates: [Date]
    var bars: [Bar]

    init(points: [DeckStatistics.ProgressPoint]) {
        self.points = points
        dates = points.map { chartDate(forDay: $0.day) }
        bars = zip(points, dates).flatMap { point, date in
            let counts = MaturityCategory.counts(fromBins: point.bins)
            // Most solid at the bottom of each stack.
            return MaturityCategory.allCases.reversed().map { category in
                Bar(id: Bar.ID(day: point.day, category: category), date: date, category: category, count: counts[category] ?? 0)
            }
        }
    }

    /// The index of the point closest to `date`.
    func index(closestTo date: Date) -> Int? {
        dates.indices.min { abs(dates[$0].timeIntervalSince(date)) < abs(dates[$1].timeIntervalSince(date)) }
    }
}

/// The figures of the statistics screen.
///
/// Keeps each figure together with the inputs it was computed from and computes it
/// again only when they change, so hovering over a chart or switching between days,
/// weeks and months does not go over all cards again. It is not observable: the view
/// asks for the figures while it renders.
@MainActor
final class StatisticsFigures {
    private struct SummaryInputs: Equatable {
        var cards: [Card]
        var learningOptions: LearningOptions
        var calendar: StudyCalendar
        var now: Date
    }

    private struct ForecastInputs: Equatable {
        var cards: [Card]
        var calendar: StudyCalendar
        var today: Int
        var days: Int
    }

    private struct ProgressInputs: Equatable {
        var snapshots: [DailySnapshot]
        var today: Int
        var firstWeekday: Int
    }

    private var summary = Memo<SummaryInputs, DeckStatistics.Summary>()
    private var forecast = Memo<ForecastInputs, [Int]>()
    private var progress: [DeckStatistics.Granularity: Memo<ProgressInputs, ProgressSeries>] = [:]

    func summary(of deck: Deck, at now: Date, calendar: StudyCalendar) -> DeckStatistics.Summary {
        let inputs = SummaryInputs(cards: deck.cards, learningOptions: deck.learningOptions, calendar: calendar, now: now)
        return summary.value(for: inputs) {
            DeckStatistics.summary(of: deck, at: now, calendar: calendar)
        }
    }

    func forecast(of cards: [Card], calendar: StudyCalendar, today: Int, days: Int) -> [Int] {
        forecast.value(for: ForecastInputs(cards: cards, calendar: calendar, today: today, days: days)) {
            DeckStatistics.forecast(cards: cards, calendar: calendar, today: today, days: days)
        }
    }

    func progress(of snapshots: [DailySnapshot], today: Int, granularity: DeckStatistics.Granularity, firstWeekday: Int) -> ProgressSeries {
        progress[granularity, default: Memo()].value(for: ProgressInputs(snapshots: snapshots, today: today, firstWeekday: firstWeekday)) {
            ProgressSeries(points: DeckStatistics.progress(snapshots: snapshots, today: today, granularity: granularity, firstWeekday: firstWeekday))
        }
    }
}

/// A value together with the inputs it was computed from.
private struct Memo<Inputs: Equatable, Value> {
    private var entry: (inputs: Inputs, value: Value)?

    /// The stored value if `inputs` are unchanged, otherwise the result of `compute`.
    /// Cheap while nothing changed: arrays sharing storage compare equal at once.
    mutating func value(for inputs: Inputs, compute: () -> Value) -> Value {
        if let entry, entry.inputs == inputs {
            return entry.value
        }
        let value = compute()
        entry = (inputs, value)
        return value
    }
}
