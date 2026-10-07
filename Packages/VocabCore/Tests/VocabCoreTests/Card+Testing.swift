import Foundation
import VocabCore

extension Card {
    /// A card created at a fixed date, for tests that don't care when.
    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        hint: String = "",
        learningState: LearningState? = nil,
        log: [ReviewLogEntry] = []
    ) {
        self.init(
            id: id,
            question: question,
            answer: answer,
            hint: hint,
            created: Date(timeIntervalSince1970: 1_791_216_000),
            learningState: learningState,
            log: log
        )
    }
}
