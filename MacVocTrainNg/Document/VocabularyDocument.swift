import Combine
import SwiftUI
import UniformTypeIdentifiers
import VocabCore
import os

/// The SwiftUI document of one deck.
///
/// All changes go through methods that register undo actions. Besides providing
/// undo, this is how SwiftUI learns that the document has unsaved changes.
///
/// Who wants to hear of changes to the deck uses one of two ways, depending on what
/// it is:
/// - Views watch the document with `@ObservedObject`. `objectWillChange` sends before
///   every change, as SwiftUI expects.
/// - Everything else, like `DueCardCounter` and `SessionViewModel`, subscribes to
///   `deckDidChange`. It sends after every change, once `deck` holds the new state.
///
/// Why the document doesn't switch to Observation: `docs/adr/0003-dokument-bleibt-observableobject.md`.
///
/// The document lives on the main actor, so the compiler checks that the deck is only
/// read and changed there. Initializers and the requirements of `ReferenceFileDocument`
/// are `nonisolated`: SwiftUI creates and opens documents and writes snapshots to file
/// wrappers off the main actor. `snapshot` doesn't read `deck`: NSDocument takes it on
/// a background thread when a new deck is saved for the first time, while the main
/// thread waits for it. It reads `savedDeck` instead, a copy behind a lock.
@MainActor
final class VocabularyDocument: ReferenceFileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    /// Not `@Published`: a nonisolated initializer can't set a property wrapper of the
    /// main actor. `objectWillChange` sends just like it would.
    private(set) var deck: Deck {
        willSet { objectWillChange.send() }
        didSet {
            savedDeck.withLock { [deck] in $0 = deck }
            deckDidChange.send()
        }
    }
    /// The deck for `snapshot`, which may run on any thread. Kept equal to `deck`;
    /// a copy costs little, as `Deck` copies its storage only on write.
    private let savedDeck: OSAllocatedUnfairLock<Deck>
    /// Sends after every change to `deck`, once it holds the new state. Observers
    /// other than views use this, see the type's documentation.
    let deckDidChange = PassthroughSubject<Void, Never>()
    /// The study days of reviews, statistics and export. The machine's time zone,
    /// unless a test passes a fixed one.
    let calendar: StudyCalendar
    /// The time of reviews, of today's snapshot and of which cards are due.
    let clock: StudyClock
    /// The number of cards due now, kept up to date as time passes.
    private(set) lazy var dueCards = DueCardCounter(document: self)
    /// Remembers the encoded review log between saves, so autosave stays cheap.
    /// Thread-safe on its own, as saving uses it on a background thread.
    private let reviewLog = ReviewLogEncoder()

    nonisolated init(deck: Deck = Deck(), clock: StudyClock = .system, calendar: StudyCalendar = StudyCalendar()) {
        self.deck = deck
        savedDeck = OSAllocatedUnfairLock(initialState: deck)
        self.clock = clock
        self.calendar = calendar
    }

    nonisolated required init(configuration: ReadConfiguration) throws {
        clock = .system
        calendar = StudyCalendar()
        let deck: Deck
        do {
            deck = try DeckFile.decode(configuration.file)
        } catch let DeckFile.Error.damagedReviewLog(line) {
            throw AppError(String(localized: "The review log of this deck is damaged (line \(line))."))
        } catch DeckFile.Error.unsupportedVersion {
            throw AppError(String(localized: "This deck was created by a newer version of MacVocTrain."))
        } catch DeckFile.Error.outdatedVersion {
            throw AppError(String(localized: "This deck was saved by a test version of MacVocTrain from before its first release and can no longer be opened."))
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.deck = deck
        savedDeck = OSAllocatedUnfairLock(initialState: deck)
    }

    /// Runs on the main thread or, for the first save of a new deck, on a background thread.
    nonisolated func snapshot(contentType: UTType) throws -> Deck {
        savedDeck.withLock { $0 }
    }

    nonisolated func fileWrapper(snapshot: Deck, configuration: WriteConfiguration) throws -> FileWrapper {
        try DeckFile.fileWrapper(for: snapshot, reviewLog: reviewLog)
    }

    // MARK: - Queries

    func card(withID id: Card.ID) -> Card? {
        deck.card(withID: id)
    }

    // MARK: - Changes

    /// Appends a new card with `text`, created now by the document's clock, see
    /// `DeckChange.adding(_:to:)`. Returns the ID of the new card.
    @discardableResult
    func add(_ text: CardText, undoManager: UndoManager?) -> Card.ID {
        let card = Card(text: text, created: clock.now)
        if let change = DeckChange.adding([card], to: deck) {
            perform(change, actionName: String(localized: "Add Card"), undoManager: undoManager)
        }
        return card.id
    }

    /// Appends cards from an import as one change, see `DeckChange.adding(_:to:)`.
    func importCards(_ cards: [Card], undoManager: UndoManager?) {
        guard let change = DeckChange.adding(cards, to: deck) else { return }
        perform(change, actionName: String(localized: "Import Cards"), undoManager: undoManager)
    }

    /// Changes question, answer and hint of a card, see `DeckChange.editingText(of:to:in:)`.
    func editText(of id: Card.ID, to text: CardText, undoManager: UndoManager?) {
        guard let change = DeckChange.editingText(of: id, to: text, in: deck) else { return }
        perform(change, actionName: String(localized: "Edit Card"), undoManager: undoManager)
    }

    func delete(_ ids: Set<Card.ID>, undoManager: UndoManager?) {
        guard let change = DeckChange.removing(ids, from: deck) else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(change, actionName: name, undoManager: undoManager)
    }

    func resetLearningState(of ids: Set<Card.ID>, undoManager: UndoManager?) {
        guard let change = DeckChange.resettingLearningState(of: ids, in: deck) else { return }
        perform(change, actionName: String(localized: "Reset Learning State"), undoManager: undoManager)
    }

    /// Stores a card rescheduled after a review in a study session, with the change
    /// `SessionMode.grade(_:in:at:)` returns. The session registers its own undo for
    /// its place, see `SessionViewModel.grade`.
    func applyReview(_ change: DeckChange, undoManager: UndoManager?) {
        perform(change, actionName: String(localized: "Review"), undoManager: undoManager)
    }

    /// Changes the learning options, see `DeckChange.changingLearningOptions(_:in:calendar:)`.
    func updateLearningOptions(_ learningOptions: LearningOptions, undoManager: UndoManager?) {
        guard let change = DeckChange.changingLearningOptions(learningOptions, in: deck, calendar: calendar) else { return }
        perform(change, actionName: String(localized: "Change Learning Options"), undoManager: undoManager)
    }

    // MARK: - Undo machinery

    /// Applies `change` and registers its inverse as the undo action.
    private func perform(_ change: DeckChange, actionName: String, undoManager: UndoManager?) {
        var deck = deck
        let inverse = deck.apply(change, day: calendar.dayNumber(for: clock.now))
        self.deck = deck
        undoManager?.registerMainActorUndo(withTarget: self, actionName: actionName) { document, undoManager in
            document.perform(inverse, actionName: actionName, undoManager: undoManager)
        }
    }
}

/// An error with a user-facing message.
struct AppError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
