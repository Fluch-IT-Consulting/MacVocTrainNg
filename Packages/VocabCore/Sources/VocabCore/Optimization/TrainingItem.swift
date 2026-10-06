import Foundation

/// One review as the optimizer sees it.
struct TrainingReview: Hashable, Sendable {
    var grade: Grade
    /// Whole study days since the previous review of the card; 0 for the first review
    /// and for reviews on the same study day.
    var elapsedDays: Int
}

/// A review to predict together with all reviews of the same card before it
/// (`FSRSItem` in fsrs-rs). The last review is the target.
struct TrainingItem: Hashable, Sendable {
    var reviews: [TrainingReview]

    var target: TrainingReview { reviews[reviews.count - 1] }
    var history: ArraySlice<TrainingReview> { reviews.dropLast() }

    /// Reviews on a later study day than the previous one.
    var longTermReviewCount: Int { reviews.count { $0.elapsedDays > 0 } }

    var firstLongTermReview: TrainingReview? { reviews.first { $0.elapsedDays > 0 } }

    /// Lapses before the target: Again on a later study day than the previous review.
    var lapseCount: Int { history.count { $0.grade == .again && $0.elapsedDays > 0 } }
}

extension TrainingItem {
    /// One item for every review of `cards` on a later study day than the previous
    /// review of the same card, ordered by the time of that review, oldest first.
    ///
    /// Only cards whose review log is complete take part; see `Card.hasCompleteLog`.
    static func items(from cards: [Card], calendar: StudyCalendar) -> [TrainingItem] {
        var dated: [(date: Date, item: TrainingItem)] = []
        for card in cards where card.hasCompleteLog {
            var reviews: [TrainingReview] = []
            var previousDay: Int?
            for entry in card.log {
                let day = calendar.dayNumber(for: entry.date)
                let elapsed = previousDay.map { max(0, day - $0) } ?? 0
                reviews.append(TrainingReview(grade: entry.grade, elapsedDays: elapsed))
                previousDay = day
                if elapsed > 0 {
                    dated.append((entry.date, TrainingItem(reviews: reviews)))
                }
            }
        }
        // Stable, so items of the same moment keep the order of the cards.
        return dated.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element.item)
    }
}
