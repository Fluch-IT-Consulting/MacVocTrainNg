import Foundation

/// A session over the mistakes of an earlier session; its reviews change no card.
public struct Practice: Sendable {
    /// The state shared with study sessions. Only this type changes it.
    public private(set) var session: Session

    private let steps: Int
    /// Steps of mistakes, counted like steps in a study session.
    private var mistakeSteps: [Card.ID: Steps] = [:]

    public init(practicing cardIDs: [Card.ID], steps: Int, at now: Date, random: SeededRandom = SeededRandom()) {
        var random = random
        self.steps = steps
        session = Session(cardIDs: cardIDs.shuffled(using: &random), startedAt: now, random: random)
    }

    /// Records the review of the current card and moves on to the next one.
    public mutating func record(_ grade: Grade) {
        guard let id = session.currentCardID else { return }
        // Mistakes need steps like (re)learning cards in a study session;
        // other cards leave after one recall like cards in the review phase.
        var isDone = true
        if !grade.isRecall || session.mistakeIDs.contains(id) {
            var cardSteps = mistakeSteps[id] ?? Steps(required: steps)
            cardSteps.apply(grade)
            mistakeSteps[id] = cardSteps
            isDone = cardSteps.areEnough
        }
        session.record(grade, isDone: isDone)
    }

    /// Stops introducing new cards; only cards already asked are finished.
    public mutating func finishUp() {
        session.finishUp()
    }

    /// Drops the current card without recording a review, e.g. because it was deleted.
    public mutating func skip() {
        session.skip()
    }

    /// Ends the session immediately.
    public mutating func stop() {
        session.stop()
    }
}
