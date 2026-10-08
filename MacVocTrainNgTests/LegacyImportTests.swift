import AppKit
import Foundation
import Testing

@testable import MacVocTrain

/// The check that keeps the import from replacing an open deck (#179). It registers its
/// documents with the app's document controller, so it runs with the window tests.
extension WindowTests {
    @MainActor
    struct LegacyImportTests {
        let folder: URL
        let deck: URL

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            deck = folder.appendingPathComponent("Glossary.voctrain", isDirectory: true)
            try FileManager.default.createDirectory(at: deck, withIntermediateDirectories: true)
        }

        /// Runs `body` while a document of the shared controller has `url` open.
        private func withDocument(at url: URL, _ body: () -> Void) {
            let document = NSDocument()
            document.fileURL = url
            NSDocumentController.shared.addDocument(document)
            body()
            NSDocumentController.shared.removeDocument(document)
        }

        @Test func findsOpenDeck() throws {
            defer { try? FileManager.default.removeItem(at: folder) }
            withDocument(at: deck) {
                #expect(LegacyImport.openDeckError(at: deck)?.name == "Glossary.voctrain")
            }
        }

        /// The panel may name the file differently from the document: through a symbolic
        /// link to a folder, like `/var` for `/private/var`, and without a trailing slash.
        @Test func findsOpenDeckUnderAnotherSpelling() throws {
            defer { try? FileManager.default.removeItem(at: folder) }
            let link = folder.appendingPathComponent("Link", isDirectory: false)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
            let spelling = link.appendingPathComponent("Glossary.voctrain", isDirectory: false)
            withDocument(at: deck) {
                #expect(LegacyImport.openDeckError(at: spelling) != nil)
            }
        }

        @Test func letsOtherDeckThrough() throws {
            defer { try? FileManager.default.removeItem(at: folder) }
            let other = folder.appendingPathComponent("Other.voctrain", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            withDocument(at: deck) {
                #expect(LegacyImport.openDeckError(at: other) == nil)
                #expect(LegacyImport.openDeckError(at: folder.appendingPathComponent("New.voctrain")) == nil)
            }
        }

        @Test func letsClosedDeckThrough() throws {
            defer { try? FileManager.default.removeItem(at: folder) }
            #expect(LegacyImport.openDeckError(at: deck) == nil)
        }
    }
}
