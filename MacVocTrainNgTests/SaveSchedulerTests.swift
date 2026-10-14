import Foundation
import Testing

@testable import MacVocTrain

/// Saving a few seconds after every change (#252, #298).
@MainActor
struct SaveSchedulerTests {
    let saves = SaveCounter()

    func makeScheduler(delay: Duration) -> SaveScheduler {
        SaveScheduler(delay: delay) { [saves] in
            guard saves.canSave else { return nil }
            saves.count += 1
            return Task {}
        }
    }

    @Test func changesInARowAreSavedOnce() async {
        let scheduler = makeScheduler(delay: .zero)

        scheduler.changed()
        scheduler.changed()
        await scheduler.saving?.value
        #expect(saves.count == 1)
    }

    @Test func flushSavesAWaitingChangeAtOnce() async {
        let scheduler = makeScheduler(delay: .seconds(3600))

        scheduler.changed()
        scheduler.flush()
        await scheduler.saving?.value
        #expect(saves.count == 1)

        scheduler.flush()
        await scheduler.saving?.value
        #expect(saves.count == 1)
    }

    @Test func flushWithoutAChangeSavesNothing() async {
        let scheduler = makeScheduler(delay: .zero)

        scheduler.flush()
        await scheduler.saving?.value
        #expect(saves.count == 0)
    }

    /// E.g. the file can no longer be changed when the save is due.
    @Test func aSaveWithNowhereToSaveIsLeftOut() async {
        let scheduler = makeScheduler(delay: .zero)
        saves.canSave = false

        scheduler.changed()
        await scheduler.saving?.value
        #expect(saves.count == 0)
    }
}

/// Counts the saves a `SaveScheduler` starts.
@MainActor
final class SaveCounter {
    var count = 0
    /// Whether there is somewhere to save to.
    var canSave = true
}
