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
/// state that lives outside the document (e.g. the position in a study session).
struct UndoHook {
    var forward: @MainActor () -> Void
    var backward: @MainActor () -> Void

    var inverted: UndoHook { UndoHook(forward: backward, backward: forward) }
}

/// A vocabulary deck document.
///
/// All changes go through methods that register undo actions. Besides providing
/// undo, this is how SwiftUI learns that the document has unsaved changes.
///
/// `@unchecked Sendable` is required by `ReferenceFileDocument`. It is safe because
/// the deck is only changed by the `@MainActor` methods below, and SwiftUI takes
/// snapshots for saving on the main thread as well.
final class VocabularyDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    @Published private(set) var deck: Deck
    let calendar = StudyCalendar()
    /// Remembers the encoded review log between saves, so autosave stays cheap.
    private let reviewLog = ReviewLogEncoder()

    init(deck: Deck = Deck()) {
        self.deck = deck
    }

    required init(configuration: ReadConfiguration) throws {
        do {
            deck = try DeckFile.decode(configuration.file)
        } catch let DeckFile.Error.damagedReviewLog(line) {
            throw AppError(String(localized: "The review log of this deck is damaged (line \(line))."))
        } catch DeckFile.Error.unsupportedVersion {
            throw AppError(String(localized: "This deck was created by a newer version of MacVocTrain."))
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

    func dueCount(at date: Date = Date()) -> Int {
        deck.cards.reduce(0) { $0 + ($1.isDue(at: date) ? 1 : 0) }
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
        perform(CardChange(upserts: [(card, nil)]), actionName: String(localized: "Add Card"), undoManager: undoManager)
    }

    @MainActor
    func update(_ card: Card, actionName: String = String(localized: "Edit Card"), undoManager: UndoManager?) {
        guard deck.card(withID: card.id) != card else { return }
        perform(CardChange(upserts: [(card, nil)]), actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    func delete(_ ids: Set<Card.ID>, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(CardChange(removals: Array(ids)), actionName: name, undoManager: undoManager)
    }

    @MainActor
    func resetProgress(of ids: Set<Card.ID>, undoManager: UndoManager?) {
        let cards = ids.compactMap(deck.card(withID:)).filter { !$0.isNew || !$0.log.isEmpty }.map { card in
            var card = card
            card.resetProgress()
            return (card, Int?.none)
        }
        guard !cards.isEmpty else { return }
        perform(CardChange(upserts: cards), actionName: String(localized: "Reset Learning State"), undoManager: undoManager)
    }

    /// Stores a card rescheduled after an answer in a study session.
    @MainActor
    func applyReview(_ card: Card, undoManager: UndoManager?, hook: UndoHook) {
        perform(CardChange(upserts: [(card, nil)]), actionName: String(localized: "Review"), undoManager: undoManager, hook: hook)
    }

    @MainActor
    func updateSettings(_ settings: DeckSettings, undoManager: UndoManager?) {
        let old = deck.settings
        guard old != settings else { return }
        deck.settings = settings
        // Undo handlers run on the main thread, where the undo manager lives.
        nonisolated(unsafe) let undoManager = undoManager
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.updateSettings(old, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(String(localized: "Change Learning Options"))
    }

    // MARK: - Undo machinery

    private struct CardChange {
        /// Cards to replace (matched by ID) or insert at the given index (appended if `nil`).
        var upserts: [(card: Card, index: Int?)] = []
        var removals: [Card.ID] = []
    }

    @MainActor
    private func perform(_ change: CardChange, actionName: String, undoManager: UndoManager?, hook: UndoHook? = nil) {
        let inverse = apply(change)
        // Undo handlers run on the main thread, where the undo manager lives.
        nonisolated(unsafe) let undoManager = undoManager
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.perform(inverse, actionName: actionName, undoManager: undoManager, hook: hook?.inverted)
                hook?.backward()
            }
        }
        undoManager?.setActionName(actionName)
    }

    /// Applies `change` and returns the change that reverts it.
    @MainActor
    private func apply(_ change: CardChange) -> CardChange {
        var deck = deck
        var inverse = CardChange()

        let removalIndices = change.removals.compactMap(deck.index(of:)).sorted(by: >)
        for index in removalIndices {
            inverse.upserts.append((deck.cards.remove(at: index), index))
        }
        inverse.upserts.reverse() // re-insert in ascending order

        for (card, position) in change.upserts {
            if let index = deck.index(of: card.id) {
                inverse.upserts.append((deck.cards[index], nil))
                deck.cards[index] = card
            } else {
                deck.cards.insert(card, at: min(position ?? deck.cards.count, deck.cards.count))
                inverse.removals.append(card.id)
            }
        }

        deck.updateHistory(day: calendar.dayNumber(for: Date()))
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
