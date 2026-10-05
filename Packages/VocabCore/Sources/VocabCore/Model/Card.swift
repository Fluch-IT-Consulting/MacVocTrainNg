import Foundation

/// How well a card was remembered. Raw values match the FSRS rating scale.
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
public enum LearningPhase: String, Codable, Sendable {
    /// Seen for the first time; must be answered correctly a few times before it graduates.
    case learning
    /// Graduated; scheduled by FSRS in whole days.
    case review
    /// Forgotten after graduating; must be re-learned before it is scheduled again.
    case relearning
}

/// The FSRS memory model of a card plus its scheduling information.
public struct MemoryState: Codable, Hashable, Sendable {
    public var phase: LearningPhase
    /// Number of successful answers since entering (re)learning. Unused in `.review`.
    public var step: Int
    /// Days until the probability of recall drops to 90 %.
    public var stability: Double
    /// Inherent difficulty of the card, between 1 (easy) and 10 (hard).
    public var difficulty: Double
    public var lastReview: Date
    public var due: Date
    public var reps: Int
    public var lapses: Int

    public init(
        phase: LearningPhase,
        step: Int = 0,
        stability: Double,
        difficulty: Double,
        lastReview: Date,
        due: Date,
        reps: Int = 0,
        lapses: Int = 0
    ) {
        self.phase = phase
        self.step = step
        self.stability = stability
        self.difficulty = difficulty
        self.lastReview = lastReview
        self.due = due
        self.reps = reps
        self.lapses = lapses
    }
}

/// One answer given during a study session.
public struct ReviewLogEntry: Codable, Hashable, Sendable {
    public var date: Date
    public var grade: Grade

    public init(date: Date, grade: Grade) {
        self.date = date
        self.grade = grade
    }
}

/// A vocabulary index card.
public struct Card: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var question: String
    public var answer: String
    /// Optional hint shown together with the question.
    public var remark: String
    public var created: Date
    /// `nil` while the card has never been studied.
    public var memory: MemoryState?
    /// Complete review history, oldest first. Kept so FSRS parameters can be optimised later.
    public var log: [ReviewLogEntry]

    public init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        remark: String = "",
        created: Date = Date(),
        memory: MemoryState? = nil,
        log: [ReviewLogEntry] = []
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.remark = remark
        self.created = created
        self.memory = memory
        self.log = log
    }

    public var isNew: Bool { memory == nil }

    /// New cards are always due.
    public func isDue(at date: Date) -> Bool {
        guard let memory else { return true }
        return memory.due <= date
    }

    /// Forgets all learning progress but keeps the content.
    public mutating func resetProgress() {
        memory = nil
        log = []
    }
}

extension Card: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, question, answer, remark, created, memory, log
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decode(String.self, forKey: .answer)
        remark = try container.decodeIfPresent(String.self, forKey: .remark) ?? ""
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        memory = try container.decodeIfPresent(MemoryState.self, forKey: .memory)
        log = try container.decodeIfPresent([ReviewLogEntry].self, forKey: .log) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(answer, forKey: .answer)
        if !remark.isEmpty { try container.encode(remark, forKey: .remark) }
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(memory, forKey: .memory)
        if !log.isEmpty { try container.encode(log, forKey: .log) }
    }
}
