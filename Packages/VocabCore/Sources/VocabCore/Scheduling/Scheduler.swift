import Foundation

/// Applies answers to cards: updates the FSRS memory state, moves cards between
/// learning phases and computes the next due date.
///
/// Policy:
/// - New and forgotten cards stay in (re)learning until they were answered with
///   `.good` `settings.learningSteps` times (`.hard` keeps the step, `.again`
///   restarts, `.easy` graduates at once). While (re)learning they remain due.
/// - Graduated cards get an interval in whole study days from FSRS.
public struct Scheduler: Sendable {
    public var settings: DeckSettings
    public var calendar: StudyCalendar

    public init(settings: DeckSettings, calendar: StudyCalendar = StudyCalendar()) {
        self.settings = settings
        self.calendar = calendar
    }

    public var fsrs: FSRS { FSRS(parameters: settings.parameters) }

    private var requiredSteps: Int { max(1, settings.learningSteps) }

    public func review<R: RandomNumberGenerator>(_ card: Card, grade: Grade, at now: Date, using random: inout R) -> Card {
        let previous = card.memory
        let elapsedDays = previous.map { max(0, calendar.days(from: $0.lastReview, to: now)) } ?? 0
        let memory = fsrs.review(
            previous.map { FSRS.Memory(stability: $0.stability, difficulty: $0.difficulty) },
            elapsedDays: elapsedDays,
            grade: grade
        )

        var phase = previous?.phase ?? .learning
        var step = previous?.step ?? 0
        var lapses = previous?.lapses ?? 0

        switch phase {
        case .review:
            if grade == .again {
                phase = .relearning
                step = 0
                lapses += 1
            }
        case .learning, .relearning:
            switch grade {
            case .again: step = 0
            case .hard: break
            case .good: step += 1
            case .easy: step = requiredSteps
            }
            if step >= requiredSteps {
                phase = .review
                step = 0
            }
        }

        let due: Date
        if phase == .review {
            let days = intervalDays(stability: memory.stability, using: &random)
            due = calendar.start(ofDay: calendar.dayNumber(for: now) + days)
        } else {
            due = now
        }

        var updated = card
        updated.memory = MemoryState(
            phase: phase,
            step: step,
            stability: memory.stability,
            difficulty: memory.difficulty,
            lastReview: now,
            due: due,
            reps: (previous?.reps ?? 0) + 1,
            lapses: lapses
        )
        updated.log.append(ReviewLogEntry(date: now, grade: grade))
        return updated
    }

    public func review(_ card: Card, grade: Grade, at now: Date) -> Card {
        var random = SystemRandomNumberGenerator()
        return review(card, grade: grade, at: now, using: &random)
    }

    /// Interval in whole days for a graduated card, fuzzed if enabled.
    public func intervalDays<R: RandomNumberGenerator>(stability: Double, using random: inout R) -> Int {
        let maximum = max(1, settings.maximumInterval)
        let raw = fsrs.interval(stability: stability, desiredRetention: settings.desiredRetention)
        guard raw.isFinite else { return raw > 0 ? maximum : 1 }
        let interval = min(max(Int(raw.rounded()), 1), maximum)
        guard settings.fuzzing else { return interval }
        return Self.fuzzed(interval: interval, maximum: maximum, using: &random)
    }

    /// Same fuzz ranges as py-fsrs: ±15 % from 2.5 days, ±10 % from 7 days, ±5 % from 20 days.
    static func fuzzed<R: RandomNumberGenerator>(interval: Int, maximum: Int, using random: inout R) -> Int {
        guard Double(interval) >= 2.5 else { return interval }
        let ranges: [(start: Double, end: Double, factor: Double)] = [
            (2.5, 7, 0.15),
            (7, 20, 0.1),
            (20, .infinity, 0.05),
        ]
        var delta = 1.0
        for range in ranges {
            delta += range.factor * max(min(Double(interval), range.end) - range.start, 0)
        }
        var lower = max(2, Int((Double(interval) - delta).rounded()))
        let upper = min(Int((Double(interval) + delta).rounded()), maximum)
        lower = min(lower, upper)
        return Int.random(in: lower...upper, using: &random)
    }
}
