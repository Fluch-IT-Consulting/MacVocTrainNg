import Foundation

/// Applies grades to cards: updates stability and difficulty with FSRS, moves cards
/// between phases and computes the next due date.
///
/// Policy:
/// - New cards and cards after a lapse stay in (re)learning until they have
///   `learningOptions.steps` steps, one per `.good` (`.hard` keeps the step, `.again`
///   resets it, `.easy` moves the card to the review phase at once). While
///   (re)learning they remain due.
/// - Cards in the review phase get an interval in whole study days from FSRS.
public struct Scheduler: Sendable {
    public var learningOptions: LearningOptions
    public var calendar: StudyCalendar

    public init(learningOptions: LearningOptions, calendar: StudyCalendar) {
        self.learningOptions = learningOptions
        self.calendar = calendar
    }

    public var fsrs: FSRS { FSRS(parameters: learningOptions.parameters) }

    /// The card after a review with `grade`, asked in `mode`; `random` fuzzes its
    /// interval if enabled.
    public func review<R: RandomNumberGenerator>(
        _ card: Card,
        grade: Grade,
        at now: Date,
        mode: ReviewMode = .typed,
        using random: inout R
    ) -> Card {
        let previous = card.learningState
        let elapsedDays = previous.map { self.elapsedDays(since: $0, at: now) } ?? 0
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
            var steps = Steps(count: step, required: learningOptions.steps)
            steps.apply(grade)
            if steps.areEnough {
                phase = .review
                step = 0
            } else {
                step = steps.count
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
        updated.learningState = LearningState(
            phase: phase,
            step: step,
            stability: memory.stability,
            difficulty: memory.difficulty,
            lastReview: now,
            due: due,
            reviews: (previous?.reviews ?? 0) + 1,
            lapses: lapses
        )
        updated.log.append(ReviewLogEntry(date: now, grade: grade, mode: mode))
        return updated
    }

    /// `card` after studying the reviews of `log` from scratch, oldest first: the
    /// learning state, phase, step, due date and counters included. The intervals are
    /// fuzzed with `random(forReviewOf:at:)`, so every device replays the same log to
    /// the same card.
    ///
    /// `log` should reach back to the card's first review; `DeckChange.merging` replays
    /// the log merged from two versions of a deck.
    func replaying(_ log: [ReviewLogEntry], of card: Card) -> Card {
        var replayed = card
        replayed.resetLearningState()
        for entry in log {
            var random = Self.random(forReviewOf: card.id, at: entry.date)
            replayed = review(replayed, grade: entry.grade, at: entry.date, mode: entry.mode, using: &random)
        }
        return replayed
    }

    /// The random source for fuzzing the review of the card with `id` at `date`, the
    /// same on every device. Counts whole seconds, like `reviews.jsonl`.
    static func random(forReviewOf id: Card.ID, at date: Date) -> SeededRandom {
        let (high, low) = withUnsafeBytes(of: id.uuid) {
            ($0.loadUnaligned(fromByteOffset: 0, as: UInt64.self), $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
        }
        let seconds = UInt64(bitPattern: Int64(date.timeIntervalSince1970.rounded(.down)))
        return SeededRandom(seed: high ^ (low &* 0x9E37_79B9_7F4A_7C15) ^ seconds)
    }

    /// The card with stability and difficulty replayed from its review log with the
    /// current parameters, or `nil` if its log is incomplete. Phase, due date and
    /// counters stay as they are.
    public func replayingMemory(of card: Card) -> Card? {
        guard card.hasCompleteLog, var learningState = card.learningState else { return nil }
        var memory: FSRS.Memory?
        var previous: Date?
        for entry in card.log {
            let elapsedDays = previous.map { max(0, calendar.days(from: $0, to: entry.date)) } ?? 0
            memory = fsrs.review(memory, elapsedDays: elapsedDays, grade: entry.grade)
            previous = entry.date
        }
        guard let memory else { return nil }
        learningState.stability = memory.stability
        learningState.difficulty = memory.difficulty
        var updated = card
        updated.learningState = learningState
        return updated
    }

    /// Recall probability at `now`, counting whole study days since the last review
    /// like `review` does; it stays 1 for the rest of the study day of a review.
    public func recallProbability(of learningState: LearningState, at now: Date) -> Double {
        fsrs.retrievability(elapsedDays: Double(elapsedDays(since: learningState, at: now)), stability: learningState.stability)
    }

    private func elapsedDays(since learningState: LearningState, at now: Date) -> Int {
        max(0, calendar.days(from: learningState.lastReview, to: now))
    }

    /// Interval in whole study days for a card in the review phase, fuzzed if enabled.
    public func intervalDays<R: RandomNumberGenerator>(stability: Double, using random: inout R) -> Int {
        let maximum = max(1, learningOptions.maximumInterval)
        let raw = fsrs.interval(stability: stability, targetRecall: learningOptions.targetRecall)
        guard raw.isFinite else { return raw > 0 ? maximum : 1 }
        // Clamped before the conversion, which traps beyond the range of Int.
        let interval = Int(min(max(raw.rounded(), 1), Double(maximum)))
        guard learningOptions.fuzzing else { return interval }
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
