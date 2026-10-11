import Combine
import Foundation
import Observation
import VocabCore

/// Keeps the deck of an open document whole when the other device, Mac or iPhone,
/// changes its file on iCloud Drive (#252, #259).
///
/// NSDocument on the Mac and UIDocument on the iPhone read the file again on their own
/// when another process writes it, and the window or scene gets a new document, see
/// `DocumentWindow` and `OpenDeck`. The merger lives as long as the window or
/// scene, so it sees each of its documents in turn:
/// - It merges the deck of the document before into the new one: NSDocument sets
///   unsaved changes aside as an `NSFileVersion` before it reads again, where the
///   learner wouldn't find them. It doesn't if the file holds nothing the deck before
///   lacks, as after reverting to a saved or older version: merging would take back
///   the revert.
/// - It merges the versions iCloud Drive keeps in conflict with the file, saves, and
///   only then marks the conflicts resolved. An unresolved conflict keeps the iPhone
///   from opening the deck. It does so after opening, after reading again and when the
///   file changes, as iCloud Drive may keep the version of this device and set the
///   other device's aside.
/// - It saves a few seconds after every change, so the other device gets reviews
///   soon and conflicts become rare. The devices take turns rather than being used
///   at the same time, and iCloud Drive takes about a minute to bring a version
///   over, so waiting a few seconds for more changes costs little.
/// - It says so when reading the file again ended a study session.
/// - It lets go of the file while the iPhone app is in the background, see `suspend()`.
///
/// Each merge is one undo action of the document, see `VocabularyDocument.merge(_:)`.
/// The merge itself is idempotent, so merging once too often does no harm.
@MainActor @Observable
final class VersionMerger {
    /// Set when reading the file again ended a study session; the window says so.
    var endedSession = false
    /// Why a version in conflict couldn't be merged; the window shows it. Each version
    /// is reported once.
    var failure: String?
    /// Whether a study session is under way; the document's view keeps it up to date
    /// through `documentSync`.
    @ObservationIgnored var isInSession = false

    /// The current document of the window or scene.
    @ObservationIgnored private(set) var document: VocabularyDocument?
    /// The file of `document` while it can be changed, else `nil`.
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var store: (any DeckVersionStore)?
    private let makeStore: @MainActor (URL, @escaping @MainActor @Sendable () -> Void) -> any DeckVersionStore
    @ObservationIgnored private var deckObservation: AnyCancellable?
    @ObservationIgnored private var reportedFailures: Set<String> = []
    /// The latest merge; merges run one after the other.
    @ObservationIgnored private(set) var merging: Task<Void, Never>?
    /// The save scheduled after the latest change.
    @ObservationIgnored private(set) var saving: Task<Void, Never>?
    /// The merge scheduled after the file changed.
    @ObservationIgnored private(set) var checking: Task<Void, Never>?
    /// The deck of the document before the current one, and whether a study session ran
    /// on it, until `takeReplaced()` merges it.
    @ObservationIgnored private var replaced: (deck: Deck, wasInSession: Bool)?
    /// Whether a change waits for the save scheduled after it.
    @ObservationIgnored private var hasUnsavedChange = false
    /// Whether the app is in the background, see `suspend()`.
    @ObservationIgnored private(set) var isSuspended = false
    /// How long a save waits for more changes.
    private let saveDelay: Duration
    /// How long a merge waits after the file changed. During a write by another
    /// process, asking the NSDocument would wait for that process, while it may wait
    /// for this one (#246): the store only learns of the change, the merge comes later.
    private let checkDelay: Duration

    init(
        saveDelay: Duration = .seconds(5),
        checkDelay: Duration = .seconds(2),
        makeStore: @escaping @MainActor (URL, @escaping @MainActor @Sendable () -> Void) -> any DeckVersionStore = { FileVersionStore(url: $0, onChange: $1) }
    ) {
        self.saveDelay = saveDelay
        self.checkDelay = checkDelay
        self.makeStore = makeStore
    }

    /// Takes `document` as the current document, saved at `fileURL`. Called by the
    /// document's view when it appears and when the file moves or can be changed or no
    /// longer. Waits for the document's undo manager: merging changes the deck.
    func attach(_ document: VocabularyDocument, fileURL: URL?, isEditable: Bool) {
        guard document.undoManager != nil else { return }
        let fileURL = isEditable ? fileURL : nil
        guard document !== self.document || fileURL != self.fileURL else { return }
        let previous = self.document
        if fileURL != self.fileURL {
            self.fileURL = fileURL
            connectStore()
        }
        if document !== previous {
            self.document = document
            deckObservation = document.deckDidChange.sink { [weak self] in self?.scheduleSave() }
            if let previous, replaced == nil {
                replaced = (previous.deck, isInSession)
            }
            isInSession = false
        }
        mergeVersions()
    }

    /// Merges the versions in conflict with the file and the deck replaced, after the
    /// merges asked for before.
    @discardableResult
    func mergeVersions() -> Task<Void, Never> {
        let before = merging
        let task = Task { [weak self] in
            await before?.value
            await self?.mergeNow()
        }
        merging = task
        return task
    }

    /// The deck of the document before, if the file holds something it lacks: another
    /// device changed the file. Waits for a file that can be changed: the iPhone reads
    /// the file again while it can't (#259), and an old version in the version browser
    /// on the Mac can't ever be changed.
    private func takeReplaced() -> Deck? {
        guard store != nil, let document, let replaced else { return nil }
        self.replaced = nil
        guard DeckChange.merging(document.deck, into: replaced.deck, calendar: document.calendar) != nil else { return nil }
        if replaced.wasInSession {
            endedSession = true
        }
        return replaced.deck
    }

    private func mergeNow() async {
        guard let document, let store else { return }
        var versions = takeReplaced().map { [$0] } ?? []
        var conflicts: [ConflictVersion] = []
        for conflict in store.unresolvedConflicts() {
            do {
                versions.append(try conflict.read())
                conflicts.append(conflict)
            } catch {
                if reportedFailures.insert(conflict.id).inserted {
                    failure = VocabularyDocument.openingError(for: error).localizedDescription
                }
            }
        }
        if document.merge(versions) {
            do {
                try await store.save()
            } catch {
                // The conflicts stay; the next merge tries again, at the latest when
                // autosave has written the file.
                return
            }
        }
        for conflict in conflicts {
            conflict.markResolved()
        }
    }

    /// Lets go of the file when the iPhone app goes to the background: a file presenter
    /// of a suspended app may hold up the other processes that want the file (#246).
    /// Saves a change first that waits for its save.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        checking?.cancel()
        if hasUnsavedChange, let store {
            saving?.cancel()
            hasUnsavedChange = false
            saving = Task { try? await store.save() }
        }
        store = nil
    }

    /// Hears of changes to the file again when the app comes back, and merges the
    /// versions that came meanwhile.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        connectStore()
        mergeVersions()
    }

    /// Hears of changes to the file while it can be changed and the app isn't in the
    /// background.
    private func connectStore() {
        store = nil
        if let fileURL, !isSuspended {
            store = makeStore(fileURL) { [weak self] in self?.fileDidChange() }
        }
    }

    private func fileDidChange() {
        checking?.cancel()
        checking = Task { [weak self, checkDelay] in
            try? await Task.sleep(for: checkDelay)
            guard !Task.isCancelled else { return }
            self?.mergeVersions()
        }
    }

    private func scheduleSave() {
        guard store != nil else { return }
        saving?.cancel()
        hasUnsavedChange = true
        saving = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled, let self else { return }
            hasUnsavedChange = false
            // A failed save leaves the change to autosave.
            try? await store?.save()
        }
    }
}

/// The file of an open deck, as far as `VersionMerger` needs it.
@MainActor
protocol DeckVersionStore: AnyObject {
    /// The versions iCloud Drive keeps in conflict with the file, as far as they are
    /// on this device.
    func unresolvedConflicts() -> [ConflictVersion]
    /// Writes the document's deck to the file now. Throws if it can't, also if it
    /// finds no document to write.
    func save() async throws
}

/// A version of the deck that iCloud Drive keeps in conflict with its file.
struct ConflictVersion {
    /// Tells the versions apart.
    var id: String
    var read: () throws -> Deck
    var markResolved: () -> Void
}
