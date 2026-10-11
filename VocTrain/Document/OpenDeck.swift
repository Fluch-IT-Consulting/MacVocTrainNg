import Combine
import Foundation
import Observation
import UIKit
import VocabCore

/// A deck the app has open (#285): its file, which a `DeckFileDocument` reads and
/// saves, and the `VocabularyDocument` the views show.
///
/// As with `DocumentGroup` before, every read of the file brings a new document: when
/// another device changed the file, the deck view starts afresh, and the
/// `VersionMerger` keeps what the document before held that the file lacks, see
/// `DeckScreen`. Changes register with the UIDocument's own undo manager, so it counts
/// them and saves them by itself; the merger saves a few seconds after each change
/// too, through the UIDocument it finds among the file presenters.
@MainActor @Observable
final class OpenDeck {
    let url: URL
    /// The document the views show, once the file has been read.
    private(set) var document: VocabularyDocument?
    /// Whether the deck can be changed now; not while the file is read again.
    private(set) var isEditable = false
    /// Why the deck couldn't be opened.
    private(set) var failure: String?
    let merger = VersionMerger()

    @ObservationIgnored private let file: DeckFileDocument
    @ObservationIgnored private let isAccessingFile: Bool
    @ObservationIgnored private var observations: [AnyCancellable] = []

    /// Opens the deck at `url`, a file the learner chose or the app remembered.
    init(url: URL) {
        self.url = url
        // A file outside the app's sandbox, as on iCloud Drive, can be read only while
        // the app accesses it, until the deck closes.
        isAccessingFile = url.startAccessingSecurityScopedResource()
        file = DeckFileDocument(fileURL: url)
        observations = [
            NotificationCenter.default.publisher(for: DeckFileDocument.didLoad, object: file)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.takeLoadedDeck() },
            NotificationCenter.default.publisher(for: UIDocument.stateChangedNotification, object: file)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateState() },
        ]
        file.open { @Sendable [weak self] success in
            Task { @MainActor [weak self] in self?.didOpen(success) }
        }
    }

    /// The name of the deck, without the extension.
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The undo manager every change of the deck registers with.
    var undoManager: UndoManager {
        file.undoManager
    }

    private func didOpen(_ success: Bool) {
        if success {
            updateState()
        } else {
            failure = file.failure ?? String(localized: "The deck could not be read.")
        }
    }

    /// Saves what is unsaved and lets go of the file.
    func close() async {
        merger.suspend()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            file.close { @Sendable _ in continuation.resume() }
        }
        if isAccessingFile {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Lets go of the file while the app is in the background, see
    /// `VersionMerger.suspend()`, and saves what is unsaved.
    func suspend() {
        merger.suspend()
        if file.hasUnsavedChanges {
            file.autosave(completionHandler: nil)
        }
    }

    func resume() {
        merger.resume()
    }

    /// Takes the deck the file just read as a new document.
    private func takeLoadedDeck() {
        guard let deck = file.takeLoadedDeck() else { return }
        let document = VocabularyDocument(deck: deck)
        file.document = document
        self.document = document
        updateState()
    }

    private func updateState() {
        let state = file.documentState
        isEditable = document != nil && !state.contains(.closed) && !state.contains(.editingDisabled)
    }
}

extension OpenDeck: Hashable {
    nonisolated static func == (lhs: OpenDeck, rhs: OpenDeck) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
