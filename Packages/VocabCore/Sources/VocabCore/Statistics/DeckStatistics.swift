import Foundation

/// Derived figures about a deck for the statistics screen.
public enum DeckStatistics {
    public enum Granularity: String, CaseIterable, Sendable {
        case day, week, month

        /// How many points a progress series shows at most.
        var pointLimit: Int? {
            switch self {
            case .day: 366
            case .week: 260
            case .month: nil
            }
        }
    }

    public struct ProgressPoint: Hashable, Sendable {
        /// Study day the point represents (the last day of its week or month).
        public var day: Int
        public var bins: [Int]
    }

    /// Card distribution over time, oldest first.
    ///
    /// Each point shows the last snapshot recorded on or before its day, so days
    /// without activity repeat the previous state.
    public static func progress(history: [DailySnapshot], today: Int, granularity: Granularity, firstWeekday: Int = 2) -> [ProgressPoint] {
        guard let first = history.first else { return [] }

        var days: [Int] = []
        var day = today
        while day >= first.day {
            days.append(day)
            if let limit = granularity.pointLimit, days.count >= limit { break }
            switch granularity {
            case .day:
                day -= 1
            case .week:
                let weekday = CivilDate.weekday(ofDayNumber: day)
                let startOfWeek = day - (weekday - firstWeekday + 7) % 7
                day = startOfWeek - 1
            case .month:
                let civil = CivilDate(dayNumber: day)
                day = CivilDate(year: civil.year, month: civil.month, day: 1).dayNumber - 1
            }
        }

        var points: [ProgressPoint] = []
        var index = history.count - 1
        for day in days {
            while index > 0, history[index].day > day {
                index -= 1
            }
            guard history[index].day <= day else { break }
            points.append(ProgressPoint(day: day, bins: history[index].bins))
        }
        return points.reversed()
    }

    /// Number of graduated cards falling due on each of the next `days` study days;
    /// index 0 includes overdue cards. Cards in (re)learning count as due today.
    public static func forecast(cards: [Card], calendar: StudyCalendar, today: Int, days: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: max(days, 1))
        for card in cards {
            guard let memory = card.memory else { continue }
            let offset = memory.phase == .review ? calendar.dayNumber(for: memory.due) - today : 0
            if offset < counts.count {
                counts[max(offset, 0)] += 1
            }
        }
        return counts
    }

    public struct Summary: Hashable, Sendable {
        public var total = 0
        public var new = 0
        public var dueNow = 0
        /// Mean probability of recall of graduated cards right now.
        public var averageRetrievability: Double?
        public var reviewsToday = 0
        public var correctToday = 0
    }

    public static func summary(of deck: Deck, at now: Date, calendar: StudyCalendar) -> Summary {
        let fsrs = FSRS(parameters: deck.settings.parameters)
        let today = calendar.dayNumber(for: now)
        var summary = Summary()
        var retrievabilitySum = 0.0
        var reviewCards = 0

        for card in deck.cards {
            summary.total += 1
            if card.isNew { summary.new += 1 }
            if card.isDue(at: now) { summary.dueNow += 1 }
            if let memory = card.memory, memory.phase == .review {
                let elapsed = now.timeIntervalSince(memory.lastReview) / 86400
                retrievabilitySum += fsrs.retrievability(elapsedDays: elapsed, stability: memory.stability)
                reviewCards += 1
            }
            for entry in card.log.reversed() {
                guard calendar.dayNumber(for: entry.date) == today else { break }
                summary.reviewsToday += 1
                if entry.grade.isRecall { summary.correctToday += 1 }
            }
        }
        if reviewCards > 0 {
            summary.averageRetrievability = retrievabilitySum / Double(reviewCards)
        }
        return summary
    }
}
