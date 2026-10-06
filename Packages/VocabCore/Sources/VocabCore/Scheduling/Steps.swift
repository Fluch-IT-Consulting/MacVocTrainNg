/// The steps a card in learning or relearning has collected, and how many it needs.
///
/// One step per `.good`; `.hard` keeps the step, `.again` resets it to zero and `.easy`
/// collects all steps at once. What happens to the count once there are enough steps
/// is up to the caller.
struct Steps: Sendable, Equatable {
    private(set) var count: Int
    /// At least 1, so every card needs one recall.
    let required: Int

    init(count: Int = 0, required: Int) {
        self.count = count
        self.required = max(1, required)
    }

    var areEnough: Bool { count >= required }

    mutating func apply(_ grade: Grade) {
        switch grade {
        case .again: count = 0
        case .hard: break
        case .good: count += 1
        case .easy: count = required
        }
    }
}
