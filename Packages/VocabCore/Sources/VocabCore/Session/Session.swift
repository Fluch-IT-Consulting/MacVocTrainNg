import Foundation

/// What a study session and practice have in common: which cards remain, which
/// one is asked, and how it went so far.
///
/// The session only tracks card IDs. Reviews are recorded through the session's
/// mode, `StudySession` or `Practice`, which decides when a card is done.
public struct Session: Sendable {
    public let id = UUID()
    public let startedAt: Date
    public private(set) var currentCardID: Card.ID?
    public private(set) var totalCount: Int
    public private(set) var reviewCount = 0
    public private(set) var recalledCount = 0
    /// Cards graded `.again` at least once, in order of their first `.again`.
    public private(set) var mistakeIDs: [Card.ID] = []

    private var queue: SessionQueue
    private var random: SeededRandom

    init(cardIDs: [Card.ID], startedAt: Date, random: SeededRandom) {
        self.startedAt = startedAt
        self.random = random
        queue = SessionQueue(cardIDs: cardIDs)
        totalCount = cardIDs.count
        advance()
    }

    public var isFinished: Bool { currentCardID == nil }
    public var remainingCount: Int { queue.count }
    public var completedCount: Int { totalCount - queue.count }
    /// Cards already asked that would still be finished by `finishUp()`.
    public var startedCount: Int { queue.startedCount }

    /// Counts the review of the current card and moves on to the next one.
    ///
    /// - Parameter isDone: Whether the current card leaves the session.
    mutating func record(_ grade: Grade, isDone: Bool) {
        guard let id = currentCardID else { return }
        reviewCount += 1
        if grade.isRecall {
            recalledCount += 1
        } else if !mistakeIDs.contains(id) {
            mistakeIDs.append(id)
        }
        if isDone {
            queue.remove(id)
        }
        advance()
    }

    /// Stops introducing new cards; only cards already asked are finished.
    public mutating func finishUp() {
        let completed = completedCount
        queue.finishUp()
        totalCount = completed + queue.count
        if let id = currentCardID, !queue.contains(id) {
            advance()
        }
    }

    /// Drops the current card without recording a review, e.g. because it was deleted.
    public mutating func skip() {
        guard let id = currentCardID else { return }
        queue.remove(id)
        totalCount -= 1
        advance()
    }

    /// Ends the session immediately.
    public mutating func stop() {
        currentCardID = nil
    }

    private mutating func advance() {
        currentCardID = queue.next(using: &random)
    }
}
