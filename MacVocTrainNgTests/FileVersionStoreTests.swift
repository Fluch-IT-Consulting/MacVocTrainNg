import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MacVocTrain

/// Saving a deck through the NSDocument behind `DocumentGroup` (#265).
@MainActor
struct FileVersionStoreTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).voctrain")

    @Test func savesThroughTheDocumentOfItsFile() async throws {
        let document = SavedDocument()
        document.fileURL = url
        document.fileType = UTType.data.identifier
        NSDocumentController.shared.addDocument(document)
        defer {
            document.close()
            try? FileManager.default.removeItem(at: url)
        }
        try await FileVersionStore.saveDocument(at: url)
        #expect(try Data(contentsOf: url) == savedContents)
    }

    @Test func savingWithoutADocumentFails() async {
        await #expect(throws: FileVersionStore.DocumentNotFound.self) {
            try await FileVersionStore.saveDocument(at: url)
        }
    }
}

/// What `SavedDocument` writes.
private let savedContents = Data("saved".utf8)

/// A document that writes the same bytes every time.
private final class SavedDocument: NSDocument {
    override class var autosavesInPlace: Bool {
        true
    }

    override func data(ofType typeName: String) throws -> Data {
        savedContents
    }
}
