import Combine
import Foundation
import Observation
import VocabCore

/// Keeps the deck of an open document whole when the other device, Mac or iPhone,
/// changes its file on iCloud Drive (#252, #259).
///
/// NSDocument on the Mac and UIDocument on the iPhone read the file again on their own
/// when another process writes it. On the Mac, the window then gets a new document, see
/// `DocumentWindow`; the iPhone app merges the file into the document it has, see
/// `OpenDeck` (#296). The merger lives as long as the window or the open deck, so it
/// sees each of its documents in turn:
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
/// - It says so when reading the file again ended a study session, on the Mac.
///
/// It leaves two jobs to types of their own (#298): `saves` saves a few seconds after
/// every change, `watch` hears of changes to the file and lets go of it while the
/// iPhone app is in the background, see `suspend()`.
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
    @ObservationIgnored private var deckObservation: AnyCancellable?
    @ObservationIgnored private var reportedFailures: Set<String> = []
    /// The latest merge; merges run one after the other.
    @ObservationIgnored private(set) var merging: Task<Void, Never>?
    /// The deck of the document before the current one, and whether a study session ran
    /// on it, until `takeReplaced()` merges it.
    @ObservationIgnored private var replaced: (deck: Deck, wasInSession: Bool)?
    /// Watches the file of `document` while it can be changed; merges when it changed.
    let watch: FileWatch
    /// Saves through the store of `watch` a few seconds after every change.
    let saves: SaveScheduler

    /// A merger for the files of the window or scene, which the app saves through
    /// `save`, see `FileVersionStore`.
    convenience init(save: @escaping FileVersionStore.Save) {
        self.init(makeStore: { url, onChange in FileVersionStore(url: url, save: save, onChange: onChange) })
    }

    /// - Parameter makeStore: Connects to the file at the URL, with the handler for its
    ///   changes.
    init(
        saveDelay: Duration = .seconds(5),
        checkDelay: Duration = .seconds(2),
        makeStore: @escaping @MainActor (URL, @escaping @MainActor @Sendable () -> Void) -> any DeckVersionStore
    ) {
        let watch = FileWatch(checkDelay: checkDelay, makeStore: makeStore)
        self.watch = watch
        saves = SaveScheduler(delay: saveDelay) { [weak watch] in
            guard let store = watch?.store else { return nil }
            // A failed save leaves the change to autosave.
            return Task { try? await store.save() }
        }
        watch.onChange = { [weak self] in self?.mergeVersions() }
    }

    /// Takes `document` as the current document, saved at `fileURL`. Called by the
    /// document's view when it appears and when the file moves or can be changed or no
    /// longer. Waits for the document's undo manager: merging changes the deck.
    func attach(_ document: VocabularyDocument, fileURL: URL?, isEditable: Bool) {
        guard document.undoManager != nil else { return }
        let fileURL = isEditable ? fileURL : nil
        guard document !== self.document || fileURL != watch.url else { return }
        let previous = self.document
        if fileURL != watch.url {
            watch.connect(fileURL)
        }
        if document !== previous {
            self.document = document
            deckObservation = document.deckDidChange.sink { [weak self] in self?.documentDidChange() }
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
    /// device changed the file. Waits for a file that can be changed: an old version in
    /// the version browser on the Mac can't ever be changed.
    private func takeReplaced() -> Deck? {
        guard watch.store != nil, let document, let replaced else { return nil }
        self.replaced = nil
        guard DeckChange.merging(document.deck, into: replaced.deck, calendar: document.calendar) != nil else { return nil }
        if replaced.wasInSession {
            endedSession = true
        }
        return replaced.deck
    }

    private func mergeNow() async {
        guard let document, let store = watch.store else { return }
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

    /// Lets go of the file when the iPhone app goes to the background, see
    /// `FileWatch.suspend()`. Saves a change first that waits for its save.
    func suspend() {
        saves.flush()
        watch.suspend()
    }

    /// Hears of changes to the file again when the app comes back, and merges the
    /// versions that came meanwhile.
    func resume() {
        guard watch.isSuspended else { return }
        watch.resume()
        mergeVersions()
    }

    /// Saves a change soon while the file can be changed and the app isn't in the
    /// background.
    private func documentDidChange() {
        guard watch.store != nil else { return }
        saves.changed()
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
