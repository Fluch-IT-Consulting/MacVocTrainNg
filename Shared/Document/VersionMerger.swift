import Combine
import Foundation
import Observation
import VocabCore

/// Keeps the deck of an open document whole when the other device, Mac or iPhone,
/// changes its file on iCloud Drive (#252, #259).
///
/// NSDocument on the Mac and UIDocument on the iPhone read the file again on their own
/// when another process writes it. Either way the merger takes in what was read, see
/// `ReadAgain` (#303), and lives as long as the window or the open deck:
/// - On the Mac, the window then gets a new document, see `DocumentWindow`. The merger
///   sees each of the window's documents in turn and merges the deck of the document
///   before into the new one: NSDocument sets unsaved changes aside as an
///   `NSFileVersion` before it reads again, where the learner wouldn't find them. It
///   doesn't if the file holds nothing the deck before lacks, as after reverting to a
///   saved or older version: merging would take back the revert.
/// - On the iPhone, the open deck keeps its document, and the merger merges the deck
///   read into it, see `merge(readAgain:)` (#296). A study session goes on.
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
    /// The decks from reading the file again that the next merge takes in.
    @ObservationIgnored private var readAgain: [ReadAgain] = []
    /// Runs after a merge took in a deck read again and changed the document. The
    /// iPhone app forgets its undo steps then (#296).
    @ObservationIgnored var didMergeReadAgain: (@MainActor () -> Void)?
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
            if let previous, !readAgain.contains(where: \.isDeckBefore) {
                readAgain.append(.deckBefore(previous.deck, wasInSession: isInSession))
            }
            isInSession = false
        }
        mergeVersions()
    }

    /// Merges `deck`, which the file holds now that the app read it again, into the
    /// document with the next merge, once the file can be changed: the iPhone app keeps
    /// its document when another device changed the file (#296).
    func merge(readAgain deck: Deck) {
        readAgain.append(.file(deck))
        mergeVersions()
    }

    /// Merges the versions in conflict with the file and the decks read again, after the
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

    /// The decks read again that `document` takes in. Leaves out the deck before if
    /// the file holds nothing it lacks; else another device changed the file, which
    /// ends a study session on the Mac.
    private func takeReadAgain(into document: VocabularyDocument) -> [ReadAgain] {
        let taken = readAgain
        readAgain = []
        return taken.filter { version in
            guard case let .deckBefore(deck, wasInSession) = version else { return true }
            guard DeckChange.merging(document.deck, into: deck, calendar: document.calendar) != nil else { return false }
            if wasInSession {
                endedSession = true
            }
            return true
        }
    }

    /// Waits for a file that can be changed: an old version in the version browser on
    /// the Mac can't ever be changed.
    private func mergeNow() async {
        guard let document, let store = watch.store else { return }
        let taken = takeReadAgain(into: document)
        var versions = taken.map(\.deck)
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
        let merged = document.merge(versions)
        if merged, !taken.isEmpty {
            didMergeReadAgain?()
        }
        // The file read again takes the document as saved, but it may lack changes
        // made before.
        let fileLacksChanges = taken.contains { version in
            guard case let .file(deck) = version else { return false }
            return DeckChange.merging(document.deck, into: deck, calendar: document.calendar) != nil
        }
        if merged || fileLacksChanges {
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

/// A deck from reading the file of an open deck again, for `VersionMerger` (#303).
private enum ReadAgain {
    /// What the file holds now, which the iPhone app read into the document it keeps.
    case file(Deck)
    /// The deck of the document before, which the Mac replaced with a new one, and
    /// whether a study session ran on it.
    case deckBefore(Deck, wasInSession: Bool)

    var deck: Deck {
        switch self {
        case let .file(deck), let .deckBefore(deck, _):
            return deck
        }
    }

    var isDeckBefore: Bool {
        guard case .deckBefore = self else { return false }
        return true
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
