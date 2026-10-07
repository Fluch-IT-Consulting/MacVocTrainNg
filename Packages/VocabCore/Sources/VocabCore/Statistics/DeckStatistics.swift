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
    public static func progress(snapshots: [DailySnapshot], today: Int, granularity: Granularity, firstWeekday: Int = 2) -> [ProgressPoint] {
        guard let first = snapshots.first else { return [] }

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
        var index = snapshots.count - 1
        for day in days {
            while index > 0, snapshots[index].day > day {
                index -= 1
            }
            guard snapshots[index].day <= day else { break }
            points.append(ProgressPoint(day: day, bins: snapshots[index].bins))
        }
        return points.reversed()
    }

    /// Number of cards in the review phase falling due on each of the next `days` study days;
    /// index 0 includes overdue cards. Cards in (re)learning count as due today.
    public static func forecast(cards: [Card], calendar: StudyCalendar, today: Int, days: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: max(days, 1))
        for card in cards {
            guard let learningState = card.learningState else { continue }
            let offset = learningState.phase == .review ? calendar.dayNumber(for: learningState.due) - today : 0
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
        /// Mean recall probability of the cards in the review phase right now.
        public var averageRecallProbability: Double?
        public var reviewsToday = 0
        public var recalledToday = 0
    }

    public static func summary(of deck: Deck, at now: Date, calendar: StudyCalendar) -> Summary {
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        let today = calendar.dayNumber(for: now)
        var summary = Summary()
        summary.dueNow = deck.dueCount(at: now)
        var recallProbabilitySum = 0.0
        var reviewCards = 0

        for card in deck.cards {
            summary.total += 1
            if card.isNew { summary.new += 1 }
            if let learningState = card.learningState, learningState.phase == .review {
                recallProbabilitySum += scheduler.recallProbability(of: learningState, at: now)
                reviewCards += 1
            }
            for entry in card.log.reversed() {
                guard calendar.dayNumber(for: entry.date) == today else { break }
                summary.reviewsToday += 1
                if entry.grade.isRecall { summary.recalledToday += 1 }
            }
        }
        if reviewCards > 0 {
            summary.averageRecallProbability = recallProbabilitySum / Double(reviewCards)
        }
        return summary
    }
}
