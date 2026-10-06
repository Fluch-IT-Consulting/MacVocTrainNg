import AppKit
import UniformTypeIdentifiers
import VocabCore

/// "Import MacVocTrain 1 Document…": converts an `.mvt` file into a new deck file
/// and opens it. The original file is only read, never changed.
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
        guard savePanel.runModal() == .OK, let target = savePanel.url else { return }

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

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Import failed")
        alert.informativeText = message
        alert.runModal()
    }
}
