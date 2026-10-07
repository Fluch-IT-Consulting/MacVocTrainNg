import Foundation

/// How well the learner knew a card. Raw values match FSRS ratings 1–4.
public enum Grade: Int, Codable, Sendable, CaseIterable, Comparable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    /// Every grade except `.again` counts as a successful recall.
    public var isRecall: Bool { self != .again }

    public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a card currently is in its learning life cycle.
public enum LearningPhase: Sendable {
    /// After the first review, until the card has collected enough steps.
    case learning
    /// Learned; scheduled by FSRS in whole study days.
    case review
    /// After a lapse, until the card has collected enough steps again.
    case relearning
}

/// What the app knows about the learner's recall of a card: FSRS stability and
/// difficulty plus its phase and schedule.
public struct LearningState: Hashable, Sendable {
    public var phase: LearningPhase
    /// Steps collected since entering (re)learning. Unused in `.review`.
    public var step: Int
    /// Days until the probability of recall drops to 90 %.
    public var stability: Double
    /// Inherent difficulty of the card, between 1 (easy) and 10 (hard).
    public var difficulty: Double
    public var lastReview: Date
    public var due: Date
    public var reviews: Int
    public var lapses: Int

    public init(
        phase: LearningPhase,
        step: Int = 0,
        stability: Double,
        difficulty: Double,
        lastReview: Date,
        due: Date,
        reviews: Int = 0,
        lapses: Int = 0
    ) {
        self.phase = phase
        self.step = step
        self.stability = stability
        self.difficulty = difficulty
        self.lastReview = lastReview
        self.due = due
        self.reviews = reviews
        self.lapses = lapses
    }
}

/// One review in a study session.
public struct ReviewLogEntry: Hashable, Sendable {
    public var date: Date
    public var grade: Grade

    public init(date: Date, grade: Grade) {
        self.date = date
        self.grade = grade
    }
}

/// A question with its answer and an optional hint, asked from question to answer.
public struct Card: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var question: String
    public var answer: String
    /// Optional hint shown together with the question.
    public var hint: String
    public var created: Date
    /// `nil` while the card has never been studied.
    public var learningState: LearningState?
    /// The review log, oldest first. `FSRSOptimizer` computes parameters from it.
    public var log: [ReviewLogEntry]

    public init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        hint: String = "",
        created: Date,
        learningState: LearningState? = nil,
        log: [ReviewLogEntry] = []
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.hint = hint
        self.created = created
        self.learningState = learningState
        self.log = log
    }

    public var isNew: Bool { learningState == nil }

    /// Whether the review log reaches back to the card's first review. Cards imported
    /// from MacVocTrain 1 with a learning state lack the reviews before the import.
    public var hasCompleteLog: Bool {
        !log.isEmpty && learningState?.reviews == log.count
    }

    /// New cards are always due.
    public func isDue(at date: Date) -> Bool {
        guard let learningState else { return true }
        return learningState.due <= date
    }

    /// Makes the card a new card again but keeps its content.
    public mutating func resetLearningState() {
        learningState = nil
        log = []
    }
}
