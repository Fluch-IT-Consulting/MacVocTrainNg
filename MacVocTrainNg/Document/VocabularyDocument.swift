import Combine
import SwiftUI
import UniformTypeIdentifiers
import VocabCore

extension UTType {
    /// Decks of this app: packages with the extension `.voctrain` (see `DeckFile`).
    /// Single JSON files of format version 1 carry the same type.
    static let vocabularyDeck = UTType(exportedAs: "com.mfluch.voctrain.deck", conformingTo: .package)
    /// Documents of MacVocTrain 1 (`.mvt`), which can be imported.
    static let legacyMacVocTrain = UTType(importedAs: "com.mfluch.MacVocTrain", conformingTo: .data)
}

extension UndoManager {
    /// Registers `handler` as the undo action for `target` and names it. The handler
    /// gets the undo manager, so it can register the redo action.
    ///
    /// Undo handlers run on the main thread, where the undo manager lives. This is
    /// the one place that tells the compiler so.
    @MainActor
    func registerMainActorUndo<Target: AnyObject & Sendable>(
        withTarget target: Target,
        actionName: String,
        handler: @escaping @MainActor (Target, UndoManager) -> Void
    ) {
        nonisolated(unsafe) let undoManager = self
        registerUndo(withTarget: target) { target in
            MainActor.assumeIsolated {
                handler(target, undoManager)
            }
        }
        setActionName(actionName)
    }
}

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
/// wrappers off the main actor. Apart from the initializers, only `snapshot` reads
/// `deck`, and it checks that it runs on the main actor.
@MainActor
final class VocabularyDocument: ReferenceFileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    /// Not `@Published`: a nonisolated initializer can't set a property wrapper of the
    /// main actor. `objectWillChange` sends just like it would.
    private(set) var deck: Deck {
        willSet { objectWillChange.send() }
        didSet { deckDidChange.send() }
    }
    /// Sends after every change to `deck`, once it holds the new state. Observers
    /// other than views use this, see the type's documentation.
    let deckDidChange = PassthroughSubject<Void, Never>()
    let calendar = StudyCalendar()
    /// The time of reviews, of today's snapshot and of which cards are due.
    let clock: StudyClock
    /// The number of cards due now, kept up to date as time passes.
    private(set) lazy var dueCards = DueCardCounter(document: self)
    /// Remembers the encoded review log between saves, so autosave stays cheap.
    /// Thread-safe on its own, as saving uses it on a background thread.
    private let reviewLog = ReviewLogEncoder()

    nonisolated init(deck: Deck = Deck(), clock: StudyClock = .system) {
        self.deck = deck
        self.clock = clock
    }

    nonisolated required init(configuration: ReadConfiguration) throws {
        clock = .system
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
    }

    /// SwiftUI takes snapshots on the main thread; this traps if it ever doesn't.
    nonisolated func snapshot(contentType: UTType) throws -> Deck {
        MainActor.assumeIsolated { deck }
    }

    nonisolated func fileWrapper(snapshot: Deck, configuration: WriteConfiguration) throws -> FileWrapper {
        try DeckFile.fileWrapper(for: snapshot, reviewLog: reviewLog)
    }

    // MARK: - Queries

    func card(withID id: Card.ID) -> Card? {
        deck.card(withID: id)
    }

    /// Cards due at `date`, by default now according to `clock`.
    func dueCount(at date: Date? = nil) -> Int {
        let date = date ?? clock.now
        return deck.cards.reduce(0) { $0 + ($1.isDue(at: date) ? 1 : 0) }
    }

    /// Cards with the same question as `question`, see `CardText.key(forQuestion:)`.
    func cards(withQuestion question: String) -> [Card] {
        let key = CardText.key(forQuestion: question)
        guard !key.isEmpty else { return [] }
        return deck.cards.filter { CardText.key(forQuestion: $0.question) == key }
    }

    // MARK: - Changes

    func add(_ card: Card, undoManager: UndoManager?) {
        perform(DeckChange(upserts: [(card, nil)]), actionName: String(localized: "Add Card"), undoManager: undoManager)
    }

    /// Appends cards from an import as one change.
    func importCards(_ cards: [Card], undoManager: UndoManager?) {
        guard !cards.isEmpty else { return }
        perform(DeckChange(upserts: cards.map { ($0, nil) }), actionName: String(localized: "Import Cards"), undoManager: undoManager)
    }

    func update(_ card: Card, actionName: String = String(localized: "Edit Card"), undoManager: UndoManager?) {
        guard deck.card(withID: card.id) != card else { return }
        perform(DeckChange(upserts: [(card, nil)]), actionName: actionName, undoManager: undoManager)
    }

    func delete(_ ids: Set<Card.ID>, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(DeckChange(removals: Array(ids)), actionName: name, undoManager: undoManager)
    }

    func resetLearningState(of ids: Set<Card.ID>, undoManager: UndoManager?) {
        let cards = deck.cards.filter { ids.contains($0.id) && (!$0.isNew || !$0.log.isEmpty) }.map { card in
            var card = card
            card.resetLearningState()
            return (card, Int?.none)
        }
        guard !cards.isEmpty else { return }
        perform(DeckChange(upserts: cards), actionName: String(localized: "Reset Learning State"), undoManager: undoManager)
    }

    /// Stores a card rescheduled after a review in a study session. The session
    /// registers its own undo for its place, see `SessionViewModel.grade`.
    func applyReview(_ card: Card, undoManager: UndoManager?) {
        perform(DeckChange(upserts: [(card, nil)]), actionName: String(localized: "Review"), undoManager: undoManager)
    }

    /// Changes the learning options. New FSRS parameters also replay stability and
    /// difficulty of every card with a complete review log; due dates stay.
    func updateLearningOptions(_ learningOptions: LearningOptions, undoManager: UndoManager?) {
        guard deck.learningOptions != learningOptions else { return }
        var change = DeckChange(learningOptions: learningOptions)
        if learningOptions.parameters != deck.learningOptions.parameters {
            let scheduler = Scheduler(learningOptions: learningOptions, calendar: calendar)
            change.upserts = deck.cards.compactMap { card -> (Card, Int?)? in
                guard let replayed = scheduler.replayingMemory(of: card), replayed != card else { return nil }
                return (replayed, nil)
            }
        }
        perform(change, actionName: String(localized: "Change Learning Options"), undoManager: undoManager)
    }

    // MARK: - Undo machinery

    private struct DeckChange {
        /// Cards to replace (matched by ID) or insert at the given index (appended if `nil`).
        var upserts: [(card: Card, index: Int?)] = []
        var removals: [Card.ID] = []
        /// New learning options; `nil` keeps them.
        var learningOptions: LearningOptions?
    }

    private func perform(_ change: DeckChange, actionName: String, undoManager: UndoManager?) {
        let inverse = apply(change)
        undoManager?.registerMainActorUndo(withTarget: self, actionName: actionName) { document, undoManager in
            document.perform(inverse, actionName: actionName, undoManager: undoManager)
        }
    }

    /// Applies `change` and returns the change that reverts it.
    private func apply(_ change: DeckChange) -> DeckChange {
        var deck = deck
        var inverse = DeckChange()

        if let learningOptions = change.learningOptions {
            inverse.learningOptions = deck.learningOptions
            deck.learningOptions = learningOptions
        }

        // Every step below passes over the cards once: a change may touch all of them.
        if !change.removals.isEmpty {
            let removals = Set(change.removals)
            // In ascending order, so undo re-inserts each card at its old index.
            inverse.upserts = deck.cards.enumerated().filter { removals.contains($0.element.id) }.map { ($0.element, $0.offset) }
            deck.cards.removeAll { removals.contains($0.id) }
        }

        var indices = Dictionary(deck.cards.enumerated().map { ($0.element.id, $0.offset) }) { first, _ in first }
        var insertions: [(card: Card, index: Int)] = []
        for (card, position) in change.upserts {
            if let index = indices[card.id] {
                inverse.upserts.append((deck.cards[index], nil))
                deck.cards[index] = card
            } else if let position {
                insertions.append((card, position))
                inverse.removals.append(card.id)
            } else {
                indices[card.id] = deck.cards.count
                deck.cards.append(card)
                inverse.removals.append(card.id)
            }
        }
        if !insertions.isEmpty {
            deck.cards = Self.inserting(insertions, into: deck.cards)
        }

        // Learning options alone move no card between the bins of a snapshot.
        if !change.upserts.isEmpty || !change.removals.isEmpty {
            deck.updateProgress(day: calendar.dayNumber(for: clock.now))
        }
        self.deck = deck
        return inverse
    }

    /// Inserts cards at their indices in one pass. Only the inverse of removals inserts
    /// at an index, in ascending order; each card lands where inserting the cards one
    /// after another would put it.
    private static func inserting(_ insertions: [(card: Card, index: Int)], into cards: [Card]) -> [Card] {
        assert(zip(insertions, insertions.dropFirst()).allSatisfy { $0.index < $1.index })
        var result: [Card] = []
        result.reserveCapacity(cards.count + insertions.count)
        var remaining = cards[...]
        for (card, index) in insertions {
            let count = min(index - result.count, remaining.count)
            result.append(contentsOf: remaining.prefix(count))
            remaining = remaining.dropFirst(count)
            result.append(card)
        }
        result.append(contentsOf: remaining)
        return result
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
