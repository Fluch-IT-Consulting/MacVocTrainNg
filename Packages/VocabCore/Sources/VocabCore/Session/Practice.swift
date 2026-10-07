import Foundation

/// A session over the mistakes of an earlier session; its reviews change no card.
/// It runs as `SessionMode.practice`.
public struct Practice: Sendable {
    /// The state shared with study sessions. Only this type changes it.
    public private(set) var session: Session

    /// Steps collected by mistakes, counted like `LearningState.step` in a study session.
    private var mistakeSteps: [Card.ID: Int] = [:]

    public init(practicing cardIDs: [Card.ID], at now: Date, random: SeededRandom = SeededRandom()) {
        var random = random
        session = Session(cardIDs: cardIDs.shuffled(using: &random), startedAt: now, random: random)
    }

    /// Records the review of the current card and moves on to the next one.
    mutating func record(_ grade: Grade, with learningOptions: LearningOptions) {
        guard let id = session.currentCardID else { return }
        // Mistakes need steps like (re)learning cards in a study session;
        // other cards leave after one recall like cards in the review phase.
        var isDone = true
        if !grade.isRecall || session.mistakeIDs.contains(id) {
            var cardSteps = Steps(count: mistakeSteps[id] ?? 0, required: learningOptions.steps)
            cardSteps.apply(grade)
            mistakeSteps[id] = cardSteps.count
            isDone = cardSteps.areEnough
        }
        session.record(grade, isDone: isDone)
    }

    mutating func perform(_ command: SessionCommand) {
        session.perform(command)
    }
}
