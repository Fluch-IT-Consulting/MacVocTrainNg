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

/// Callbacks run when an undoable change is undone or redone, so views can restore
/// state that lives outside the document (e.g. the position in a session).
struct UndoHook {
    var forward: @MainActor () -> Void
    var backward: @MainActor () -> Void

    var inverted: UndoHook { UndoHook(forward: backward, backward: forward) }
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
/// `@unchecked Sendable` is required by `ReferenceFileDocument`. It is safe because
/// the deck is only changed by the `@MainActor` methods below, and SwiftUI takes
/// snapshots for saving on the main thread as well.
final class VocabularyDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    @Published private(set) var deck: Deck {
        didSet { deckDidChange.send() }
    }
    /// Sends after every change to `deck`, once it holds the new state.
    /// `$deck` and `objectWillChange` send before the change.
    let deckDidChange = PassthroughSubject<Void, Never>()
    let calendar = StudyCalendar()
    /// The time of reviews, of today's snapshot and of which cards are due.
    let clock: StudyClock
    /// Remembers the encoded review log between saves, so autosave stays cheap.
    private let reviewLog = ReviewLogEncoder()

    init(deck: Deck = Deck(), clock: StudyClock = .system) {
        self.deck = deck
        self.clock = clock
    }

    required init(configuration: ReadConfiguration) throws {
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

    func snapshot(contentType: UTType) throws -> Deck {
        deck
    }

    func fileWrapper(snapshot: Deck, configuration: WriteConfiguration) throws -> FileWrapper {
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

    /// Cards whose question matches `question`, ignoring case and surrounding whitespace.
    func cards(withQuestion question: String) -> [Card] {
        let needle = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return deck.cards.filter {
            $0.question.trimmingCharacters(in: .whitespacesAndNewlines).compare(needle, options: [.caseInsensitive]) == .orderedSame
        }
    }

    // MARK: - Changes
    // All changes run on the main actor, which makes the class thread-safe.

    @MainActor
    func add(_ card: Card, undoManager: UndoManager?) {
        perform(DeckChange(upserts: [(card, nil)]), actionName: String(localized: "Add Card"), undoManager: undoManager)
    }

    /// Appends cards from an import as one change.
    @MainActor
    func importCards(_ cards: [Card], undoManager: UndoManager?) {
        guard !cards.isEmpty else { return }
        perform(DeckChange(upserts: cards.map { ($0, nil) }), actionName: String(localized: "Import Cards"), undoManager: undoManager)
    }

    @MainActor
    func update(_ card: Card, actionName: String = String(localized: "Edit Card"), undoManager: UndoManager?) {
        guard deck.card(withID: card.id) != card else { return }
        perform(DeckChange(upserts: [(card, nil)]), actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    func delete(_ ids: Set<Card.ID>, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(DeckChange(removals: Array(ids)), actionName: name, undoManager: undoManager)
    }

    @MainActor
    func resetLearningState(of ids: Set<Card.ID>, undoManager: UndoManager?) {
        let cards = ids.compactMap(deck.card(withID:)).filter { !$0.isNew || !$0.log.isEmpty }.map { card in
            var card = card
            card.resetLearningState()
            return (card, Int?.none)
        }
        guard !cards.isEmpty else { return }
        perform(DeckChange(upserts: cards), actionName: String(localized: "Reset Learning State"), undoManager: undoManager)
    }

    /// Stores a card rescheduled after a review in a study session.
    @MainActor
    func applyReview(_ card: Card, undoManager: UndoManager?, hook: UndoHook) {
        perform(DeckChange(upserts: [(card, nil)]), actionName: String(localized: "Review"), undoManager: undoManager, hook: hook)
    }

    /// Changes the learning options. New FSRS parameters also replay stability and
    /// difficulty of every card with a complete review log; due dates stay.
    @MainActor
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

    @MainActor
    private func perform(_ change: DeckChange, actionName: String, undoManager: UndoManager?, hook: UndoHook? = nil) {
        let inverse = apply(change)
        undoManager?.registerMainActorUndo(withTarget: self, actionName: actionName) { document, undoManager in
            document.perform(inverse, actionName: actionName, undoManager: undoManager, hook: hook?.inverted)
            hook?.backward()
        }
    }

    /// Applies `change` and returns the change that reverts it.
    @MainActor
    private func apply(_ change: DeckChange) -> DeckChange {
        var deck = deck
        var inverse = DeckChange()

        if let learningOptions = change.learningOptions {
            inverse.learningOptions = deck.learningOptions
            deck.learningOptions = learningOptions
        }

        let removalIndices = change.removals.compactMap(deck.index(of:)).sorted(by: >)
        for index in removalIndices {
            inverse.upserts.append((deck.cards.remove(at: index), index))
        }
        inverse.upserts.reverse()  // re-insert in ascending order

        for (card, position) in change.upserts {
            if let index = deck.index(of: card.id) {
                inverse.upserts.append((deck.cards[index], nil))
                deck.cards[index] = card
            } else {
                deck.cards.insert(card, at: min(position ?? deck.cards.count, deck.cards.count))
                inverse.removals.append(card.id)
            }
        }

        // Learning options alone move no card between the bins of a snapshot.
        if !change.upserts.isEmpty || !change.removals.isEmpty {
            deck.updateProgress(day: calendar.dayNumber(for: clock.now))
        }
        self.deck = deck
        return inverse
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
