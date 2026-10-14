import SwiftUI
import UniformTypeIdentifiers
import VocabCore

/// The document behind `DocumentGroup`, which only the Mac app uses; the iPhone app
/// opens and saves its decks itself (#285, #297). Everything here is `nonisolated`:
/// SwiftUI opens documents and writes snapshots to file wrappers off the main actor.
extension VocabularyDocument: ReferenceFileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    nonisolated convenience init(configuration: ReadConfiguration) throws {
        let deck: Deck
        do {
            deck = try DeckFile.decode(configuration.file)
        } catch {
            throw Self.openingError(for: error)
        }
        self.init(deck: deck)
    }

    /// Runs on the main thread or, for the first save of a new deck, on a background
    /// thread, see `deckToSave`.
    nonisolated func snapshot(contentType: UTType) throws -> Deck {
        deckToSave
    }

    nonisolated func fileWrapper(snapshot: Deck, configuration: WriteConfiguration) throws -> FileWrapper {
        try fileWrapper(for: snapshot)
    }
}
