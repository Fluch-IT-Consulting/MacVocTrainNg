import UIKit
import VocabCore
import os

/// The file of an open deck: reads it, saves it in place and reads it again when
/// another device changed it, coordinated with iCloud Drive (#285). The app keeps it
/// itself instead of leaving it to `DocumentGroup`, so it can open the deck it showed
/// last at launch, without the document browser first.
///
/// UIDocument isn't bound to the main actor: it reads and writes on a queue of its
/// own. So this class keeps what both sides need behind locks: the deck it read last,
/// until `OpenDeck` takes it, and the document whose deck it saves.
final class DeckFileDocument: UIDocument {
    /// Posted after the file was read, at opening and after another device changed it,
    /// on the queue that read it. `takeLoadedDeck()` then returns what it read.
    static let didLoad = Notification.Name("DeckFileDocument.didLoad")

    private let loadedDeck = OSAllocatedUnfairLock<Deck?>(initialState: nil)
    private let savedDocument = OSAllocatedUnfairLock<VocabularyDocument?>(initialState: nil)
    private let lastError = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// The document whose deck `contents(forType:)` saves.
    var document: VocabularyDocument? {
        get { savedDocument.withLock { $0 } }
        set { savedDocument.withLock { $0 = newValue } }
    }

    /// Why reading or saving failed last, for the learner.
    var failure: String? {
        lastError.withLock { $0 }
    }

    /// The deck read last, once.
    func takeLoadedDeck() -> Deck? {
        loadedDeck.withLock { deck in
            defer { deck = nil }
            return deck
        }
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let wrapper = contents as? FileWrapper else {
            throw VocabularyDocument.openingError(for: DeckFile.Error.notADeck)
        }
        let deck: Deck
        do {
            deck = try DeckFile.decode(wrapper)
        } catch {
            throw VocabularyDocument.openingError(for: error)
        }
        loadedDeck.withLock { $0 = deck }
        NotificationCenter.default.post(name: Self.didLoad, object: self)
    }

    override func contents(forType typeName: String) throws -> Any {
        guard let document else { throw CocoaError(.fileWriteUnknown) }
        return try document.fileWrapper()
    }

    override func handleError(_ error: any Error, userInteractionPermitted: Bool) {
        lastError.withLock { $0 = error.localizedDescription }
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}
