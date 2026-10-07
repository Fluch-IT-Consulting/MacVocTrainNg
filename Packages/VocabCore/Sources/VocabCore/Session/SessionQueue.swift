import Foundation

/// Decides in which order the cards of a session are asked.
///
/// Cards flow through three stages:
/// 1. `backlog`: all remaining cards, most urgent first.
/// 2. `staging`: the next block of up to `stagingSize` backlog cards, in random order.
/// 3. `rotation`: up to `rotationSize` cards that are asked in turn.
///
/// The next card is picked at random from the front of the rotation and then moved
/// to its end. A card graded `.again` therefore comes back after a few others, and
/// the same card is never asked twice in a row while others are left.
/// (Same idea as the IndexCardRevisionPool of MacVocTrain 1.)
struct SessionQueue: Sendable {
    static let stagingSize = 25
    static let rotationSize = 10

    private(set) var backlog: [Card.ID]
    private(set) var staging: [Card.ID] = []
    private(set) var rotation: [Card.ID] = []
    /// Cards that have been asked at least once.
    private(set) var seen: Set<Card.ID> = []

    init(cardIDs: [Card.ID]) {
        backlog = cardIDs
    }

    var count: Int { backlog.count + staging.count + rotation.count }
    var isEmpty: Bool { count == 0 }

    /// Cards asked at least once that are still in the queue.
    var startedCount: Int { rotation.filter(seen.contains).count }

    func contains(_ id: Card.ID) -> Bool {
        rotation.contains(id) || staging.contains(id) || backlog.contains(id)
    }

    mutating func next<R: RandomNumberGenerator>(using random: inout R) -> Card.ID? {
        fillRotation(using: &random)
        guard !rotation.isEmpty else { return nil }
        // Pick from the front half. The card just asked sits at the end, outside the
        // window, and moves up one place per question: no card comes twice in a row
        // while others are left, and an `.again` card returns only after at least
        // `rotation.count - window` others.
        let window = (rotation.count + 1) / 2
        let index = Int.random(in: 0..<window, using: &random)
        let id = rotation.remove(at: index)
        rotation.append(id)
        seen.insert(id)
        return id
    }

    mutating func remove(_ id: Card.ID) {
        rotation.removeAll { $0 == id }
        staging.removeAll { $0 == id }
        backlog.removeAll { $0 == id }
    }

    /// Drops every card that has not been asked yet.
    mutating func finishUp() {
        backlog.removeAll()
        staging.removeAll()
        rotation.removeAll { !seen.contains($0) }
    }

    private mutating func fillRotation<R: RandomNumberGenerator>(using random: inout R) {
        while rotation.count < Self.rotationSize, !(staging.isEmpty && backlog.isEmpty) {
            if staging.isEmpty {
                let blockSize = min(Self.stagingSize, backlog.count)
                staging = Array(backlog.prefix(blockSize)).shuffled(using: &random)
                backlog.removeFirst(blockSize)
            }
            rotation.append(staging.removeFirst())
        }
    }
}
