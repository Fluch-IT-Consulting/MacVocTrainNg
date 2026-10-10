import Foundation
import Testing

@testable import VocTrain

/// Finding the UIDocument of a deck among the file presenters (#259).
struct FileVersionStoreTests {
    let url = URL(fileURLWithPath: "/Users/learner/Library/Mobile Documents/com~apple~CloudDocs/Polish.voctrain")

    @Test func aPackageIsTheSameFileWithOrWithoutTheSlashAtTheEnd() {
        #expect(FileVersionStore.isSameFile(url, URL(fileURLWithPath: url.path + "/", isDirectory: true)))
    }

    @Test func anotherDeckIsAnotherFile() {
        #expect(!FileVersionStore.isSameFile(url, url.deletingLastPathComponent().appending(path: "German.voctrain")))
    }
}
