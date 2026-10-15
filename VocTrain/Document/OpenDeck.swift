import Combine
import Foundation
import Observation
import UIKit
import VocabCore

/// A deck the app has open (#285): its file, which a `DeckFileDocument` reads and
/// saves, and the `VocabularyDocument` the views show.
///
/// The deck keeps its document while it is open: when another device changed the file,
/// the `VersionMerger` merges what the file holds into it, and a study session goes on
/// (#296, #303). Changes register with the UIDocument's own undo manager, so it counts
/// them and saves them by itself; the merger saves a few seconds after each change too,
/// through the same UIDocument (#295).
@MainActor @Observable
final class OpenDeck {
    let url: URL
    /// The document the views show, once the file has been read.
    private(set) var document: VocabularyDocument?
    /// Whether the deck can be changed now; not while the file is read again.
    private(set) var isEditable = false
    /// Why the deck couldn't be opened.
    private(set) var failure: String?
    let merger: VersionMerger

    @ObservationIgnored private let file: DeckFileDocument
    @ObservationIgnored private let isAccessingFile: Bool
    @ObservationIgnored private var observations: [AnyCancellable] = []

    /// Opens the deck at `url`, a file the learner chose or the app remembered.
    init(url: URL) {
        self.url = url
        // A file outside the app's sandbox, as on iCloud Drive, can be read only while
        // the app accesses it, until the deck closes.
        isAccessingFile = url.startAccessingSecurityScopedResource()
        let file = DeckFileDocument(fileURL: url)
        self.file = file
        merger = VersionMerger { _ in try await file.saveInPlace() }
        merger.didMergeReadAgain = { [weak self] in self?.forgetUndoSteps() }
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

    /// Saves what is unsaved and lets go of the file. A file that failed to open is
    /// closed already.
    func close() async {
        merger.suspend()
        if !file.documentState.contains(.closed) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                file.close { @Sendable _ in continuation.resume() }
            }
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

    /// Takes the deck the file just read: as the document when the file is read first,
    /// else for the merger to merge into the document once the file can be changed
    /// again. The UIDocument then takes the file as saved; the merger saves what the
    /// document holds beyond it.
    private func takeLoadedDeck() {
        guard let deck = file.takeLoadedDeck() else { return }
        if document == nil {
            let document = VocabularyDocument(deck: deck)
            // Before anyone sees the document: changes and merges need it (#305).
            document.attachUndoManager(undoManager)
            file.document = document
            self.document = document
        } else {
            merger.merge(readAgain: deck)
        }
        updateState()
    }

    /// Attaches the document to the merger itself, not only through the deck's view:
    /// the merger waits for the file to be editable again before it merges the deck
    /// read again, and a deck may be read again while no view shows it.
    private func updateState() {
        let state = file.documentState
        isEditable = document != nil && !state.contains(.closed) && !state.contains(.editingDisabled)
        if let document {
            merger.attach(document, fileURL: url, isEditable: isEditable)
        }
    }

    /// Runs after the merger merged what another device wrote to the file (#296). Undo
    /// takes back neither the merge nor any step before it: it would take back what the
    /// other device did, or bring back cards it changed since. As on the Mac, where
    /// reading the file again ends the session, the session's steps until now can no
    /// longer be undone.
    private func forgetUndoSteps() {
        undoManager.removeAllActions()
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
