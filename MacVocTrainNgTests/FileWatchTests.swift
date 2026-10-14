import Foundation
import Testing

@testable import MacVocTrain

/// Hearing of changes to the file of an open deck (#252, #259, #298).
@MainActor
struct FileWatchTests {
    let url = URL(fileURLWithPath: "/Users/learner/Library/Mobile Documents/com~apple~CloudDocs/Polish.voctrain")
    let store = FakeVersionStore()
    let changes = ChangeCounter()

    func makeWatch() -> FileWatch {
        let watch = FileWatch(checkDelay: .zero) { [store] _, onChange in
            store.connections += 1
            store.onChange = onChange
            return store
        }
        watch.onChange = { [changes] in changes.count += 1 }
        return watch
    }

    @Test func connectsAStoreForAFileOnly() {
        let watch = makeWatch()

        watch.connect(url)
        #expect(watch.store != nil)
        #expect(store.connections == 1)

        watch.connect(nil)
        #expect(watch.store == nil)
        #expect(store.connections == 1)
    }

    @Test func changesInARowAreReportedOnce() async {
        let watch = makeWatch()
        watch.connect(url)

        store.onChange?()
        store.onChange?()
        await watch.checking?.value
        #expect(changes.count == 1)
    }

    /// The iPhone app in the background lets go of the file (#259).
    @Test func theBackgroundLetsGoOfTheFileUntilTheReturn() async {
        let watch = makeWatch()
        watch.connect(url)

        store.onChange?()
        watch.suspend()
        await watch.checking?.value
        #expect(watch.store == nil)
        #expect(changes.count == 0)

        watch.connect(url)
        #expect(watch.store == nil)

        watch.resume()
        #expect(watch.store != nil)
        #expect(store.connections == 2)
    }
}

/// Counts the changes a `FileWatch` reports.
@MainActor
final class ChangeCounter {
    var count = 0
}
