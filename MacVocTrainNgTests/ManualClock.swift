import Foundation
import VocabCore

/// A clock the test moves by hand. Only used on the main actor.
final class ManualClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    var studyClock: StudyClock { StudyClock { self.now } }
}
