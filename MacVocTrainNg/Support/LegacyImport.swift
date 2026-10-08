import AppKit
import UniformTypeIdentifiers
import VocabCore

/// "Import MacVocTrain 1 Document…": converts an `.mvt` file into a new deck file
/// and opens it. The original file is only read, never changed. A deck that is open
/// isn't replaced: its window would go on showing the old deck and save it over the
/// import (#179).
@MainActor
enum LegacyImport {
    static func run() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.legacyMacVocTrain]
        openPanel.allowsMultipleSelection = false
        openPanel.message = String(localized: "Choose a MacVocTrain 1 document (.mvt) to import.")
        openPanel.prompt = String(localized: "Import")
        guard openPanel.runModal() == .OK, let source = openPanel.url else { return }

        let deck: Deck
        do {
            deck = try LegacyImporter.importDeck(from: Data(contentsOf: source))
        } catch {
            showError(String(localized: "“\(source.lastPathComponent)” could not be read as a MacVocTrain 1 document."))
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.vocabularyDeck]
        savePanel.directoryURL = source.deletingLastPathComponent()
        savePanel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent
        savePanel.message = String(localized: "Save the imported deck with \(deck.cards.count) cards.")
        // The panel holds its delegate weakly, and an optimized build may release a local
        // after its last use, before the panel runs (#236).
        let validator = SavePanelValidator()
        savePanel.delegate = validator
        guard withExtendedLifetime(validator, { savePanel.runModal() }) == .OK, let target = savePanel.url else { return }

        // The panel has checked already; this is in case it didn't.
        if let error = openDeckError(at: target) {
            showError([error.errorDescription, error.recoverySuggestion].compactMap(\.self).joined(separator: " "))
            return
        }
        do {
            try DeckFile.fileWrapper(for: deck).write(to: target, options: .atomic, originalContentsURL: nil)
        } catch {
            showError(error.localizedDescription)
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, error in
            if let error {
                Task { @MainActor in showError(error.localizedDescription) }
            }
        }
    }

    /// The error for replacing the deck at `url`, if a document of `controller` has
    /// it open. Compares the files, not the URLs: a URL may name the file in another
    /// spelling, e.g. with a trailing slash or through a symbolic link. Nothing is open
    /// where nothing exists yet.
    static func openDeckError(at url: URL, in controller: NSDocumentController = .shared) -> DeckIsOpenError? {
        guard let target = fileIdentifier(of: url) else { return nil }
        let isOpen = controller.documents.contains { document in
            document.fileURL.flatMap { fileIdentifier(of: $0) }?.isEqual(target) ?? false
        }
        return isOpen ? DeckIsOpenError(name: url.lastPathComponent) : nil
    }

    private static func fileIdentifier(of url: URL) -> (any NSObjectProtocol)? {
        try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }

    struct DeckIsOpenError: LocalizedError {
        var name: String

        var errorDescription: String? {
            String(localized: "“\(name)” is open.")
        }

        var recoverySuggestion: String? {
            String(localized: "Close the deck before replacing it, or choose another name.")
        }
    }

    /// Keeps the save panel open while its target is an open deck; the panel shows the error.
    private final class SavePanelValidator: NSObject, NSOpenSavePanelDelegate {
        func panel(_ sender: Any, validate url: URL) throws {
            if let error = LegacyImport.openDeckError(at: url) {
                throw error
            }
        }
    }

    private static func showError(_ message: String) {
        NSAlert.showWarning(String(localized: "Import failed"), message: message)
    }
}
