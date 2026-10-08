import Foundation
import Testing

@testable import MacVocTrain

struct PresentationTests {
    @Test func dueTextTellsNewDueAndLater() {
        let now = Date()
        let later = now.addingTimeInterval(3 * 24 * 3600)
        #expect(Format.due(nil, now: now) == String(localized: "New"))
        #expect(Format.due(now, now: now) == String(localized: "Now"))
        #expect(Format.due(now.addingTimeInterval(-60), now: now) == String(localized: "Now"))
        #expect(Format.due(later, now: now) == later.formatted(.relative(presentation: .named)))
    }
}
