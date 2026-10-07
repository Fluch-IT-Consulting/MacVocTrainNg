import Foundation
@testable import VocabCore

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

    /// The card with another answer, as an edit would leave it.
    func withAnswer(_ answer: String) -> Card {
        var card = self
        card.answer = answer
        return card
    }
}
