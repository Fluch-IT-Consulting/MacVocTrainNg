import Combine
import Foundation
import Observation
import VocabCore

/// Keeps the deck of a document window whole when another device changes its file,
/// e.g. the iPhone on iCloud Drive (#252).
///
/// NSDocument reads the file again on its own when another process writes it, and the
/// window gets a new document, see `DocumentWindow`. The merger lives as long as the
/// window, so it sees each of its documents in turn:
/// - It merges the deck of the document before into the new one: NSDocument sets
///   unsaved changes aside as an `NSFileVersion` before it reads again, where the
///   learner wouldn't find them. It doesn't if the file holds nothing the deck before
///   lacks, as after reverting to a saved or older version: merging would take back
///   the revert.
/// - It merges the versions iCloud Drive keeps in conflict with the file, saves, and
///   only then marks the conflicts resolved. An unresolved conflict keeps the iPhone
///   from opening the deck. It does so after opening, after reading again and when the
///   file changes, as iCloud Drive may keep the version of this Mac and set the other
///   device's aside.
/// - It saves a few seconds after every change, so the other device gets reviews
///   soon and conflicts become rare. The devices take turns rather than being used
///   at the same time, and iCloud Drive takes about a minute to bring a version
///   over, so waiting a few seconds for more changes costs little.
/// - It says so when reading the file again ended a study session.
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
    /// Whether the window shows a study session; `DocumentView` keeps it up to date.
    @ObservationIgnored var isInSession = false

    /// The window's current document.
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

    /// Takes `document` as the window's document, saved at `fileURL`. Called by
    /// `DocumentView` when it appears and when the file moves or can be changed or no
    /// longer. Waits for the document's undo manager: merging changes the deck.
    func attach(_ document: VocabularyDocument, fileURL: URL?, isEditable: Bool) {
        guard document.undoManager != nil else { return }
        let fileURL = isEditable ? fileURL : nil
        guard document !== self.document || fileURL != self.fileURL else { return }
        let previous = self.document
        if fileURL != self.fileURL {
            self.fileURL = fileURL
            store = nil
            if let fileURL {
                store = makeStore(fileURL) { [weak self] in self?.fileDidChange() }
            }
        }
        guard document !== previous else {
            mergeVersions()
            return
        }

        self.document = document
        deckObservation = document.deckDidChange.sink { [weak self] in self?.scheduleSave() }
        var recovered: Deck?
        if let previous, store != nil, DeckChange.merging(document.deck, into: previous.deck, calendar: document.calendar) != nil {
            // The file holds something the deck before lacks: another device changed it.
            recovered = previous.deck
            if isInSession {
                endedSession = true
            }
        }
        isInSession = false
        mergeVersions(recovering: recovered)
    }

    /// Merges the versions in conflict with the file and `recovered`, after the merges
    /// asked for before.
    @discardableResult
    func mergeVersions(recovering recovered: Deck? = nil) -> Task<Void, Never> {
        let before = merging
        let task = Task { [weak self] in
            await before?.value
            await self?.mergeNow(recovering: recovered)
        }
        merging = task
        return task
    }

    private func mergeNow(recovering recovered: Deck?) async {
        guard let document, let store else { return }
        var versions = recovered.map { [$0] } ?? []
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
        saving = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            // A failed save leaves the change to autosave.
            try? await self?.store?.save()
        }
    }
}

/// The file of an open deck, as far as `VersionMerger` needs it.
@MainActor
protocol DeckVersionStore: AnyObject {
    /// The versions iCloud Drive keeps in conflict with the file, as far as they are
    /// on this Mac.
    func unresolvedConflicts() -> [ConflictVersion]
    /// Writes the document's deck to the file now.
    func save() async throws
}

/// A version of the deck that iCloud Drive keeps in conflict with its file.
struct ConflictVersion {
    /// Tells the versions apart.
    var id: String
    var read: () throws -> Deck
    var markResolved: () -> Void
}
