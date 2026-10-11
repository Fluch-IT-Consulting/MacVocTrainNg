import Foundation
import Testing
import UIKit

@testable import VocTrain

/// Finding the UIDocument of a deck among the file presenters (#259, #265).
struct FileVersionStoreTests {
    let url = URL(fileURLWithPath: "/Users/learner/Library/Mobile Documents/com~apple~CloudDocs/Polish.voctrain")

    @Test func aPackageIsTheSameFileWithOrWithoutTheSlashAtTheEnd() {
        #expect(FileVersionStore.isSameFile(url, URL(fileURLWithPath: url.path + "/", isDirectory: true)))
    }

    @Test func anotherDeckIsAnotherFile() {
        #expect(!FileVersionStore.isSameFile(url, url.deletingLastPathComponent().appending(path: "German.voctrain")))
    }

    /// If the UIDocument of an open file is no longer among the file presenters, as
    /// after a change in SwiftUI, this test fails rather than saving silently stop.
    @MainActor
    @Test func savesThroughTheOpenDocumentOfItsFile() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).voctrain")
        try Data("before".utf8).write(to: url)
        let document = SavedDocument(fileURL: url)
        #expect(await document.open())
        let store = FileVersionStore(url: url, onChange: {})

        try await store.save()
        #expect(try Data(contentsOf: url) == savedContents)
        _ = await document.close()
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    @Test func savingWithoutAnOpenDocumentFails() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).voctrain")
        let store = FileVersionStore(url: url, onChange: {})

        await #expect(throws: FileVersionStore.DocumentNotFound.self) {
            try await store.save()
        }
    }
}

/// What `SavedDocument` writes.
private let savedContents = Data("saved".utf8)

/// A document that writes the same bytes every time.
private final class SavedDocument: UIDocument {
    override func contents(forType typeName: String) throws -> Any {
        savedContents
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {}
}
