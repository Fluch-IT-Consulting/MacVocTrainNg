import Combine
import SwiftUI
import UniformTypeIdentifiers
import VocabCore
import os

/// The SwiftUI document of one deck.
///
/// All changes go through methods that register undo actions. Besides providing
/// undo, this is how SwiftUI learns that the document has unsaved changes. They
/// register with `undoManager`, which `DocumentView` sets, so no view that changes
/// the deck has to find the right undo manager itself (#48, #136).
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
    /// The study days of reviews, statistics and export. Follows the machine's time
    /// zone: when it changes, the deck counts study days in the new one at once, with
    /// the same hour for the start of a study day (#186). A test passes a fixed zone
    /// and switches with `switchTimeZone(to:)`.
    ///
    /// Not `@Published`, like `deck`. `objectWillChange` sends before every change,
    /// so the views that count study days show them anew.
    private(set) var calendar: StudyCalendar {
        willSet { objectWillChange.send() }
    }
    /// The time of reviews, of today's snapshot and of which cards are due.
    let clock: StudyClock
    /// The number of cards due now, kept up to date as time passes.
    private(set) lazy var dueCards = DueCardCounter(document: self)
    /// Remembers the encoded review log between saves, so autosave stays cheap.
    /// Thread-safe on its own, as saving uses it on a background thread.
    private let reviewLog = ReviewLogEncoder()
    /// The undo manager of the document's window; every change registers its undo
    /// action here. SwiftUI creates the document but hands the undo manager only to
    /// views, so `DocumentView` sets it, and tests set it themselves. Weak: it belongs
    /// to the NSDocument behind `DocumentGroup`. Not part of the deck, so setting it
    /// tells no observer.
    weak var undoManager: UndoManager?
    /// Switches the calendar when the machine's time zone changes; ends with the document.
    private var timeZoneObservation: AnyCancellable?

    nonisolated init(deck: Deck = Deck(), clock: StudyClock = .system, calendar: StudyCalendar = StudyCalendar()) {
        self.deck = deck
        savedDeck = OSAllocatedUnfairLock(initialState: deck)
        self.clock = clock
        self.calendar = calendar
        startFollowingSystemTimeZone()
    }

    nonisolated required init(configuration: ReadConfiguration) throws {
        clock = .system
        calendar = StudyCalendar()
        let deck: Deck
        do {
            deck = try DeckFile.decode(configuration.file)
        } catch {
            throw Self.openingError(for: error)
        }
        self.deck = deck
        savedDeck = OSAllocatedUnfairLock(initialState: deck)
        startFollowingSystemTimeZone()
    }

    /// Observes the machine's time zone from the main actor, where the calendar changes.
    /// The initializers aren't isolated to it, so the observation starts right after.
    private nonisolated func startFollowingSystemTimeZone() {
        Task { @MainActor [weak self] in
            self?.timeZoneObservation = NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.followSystemTimeZone() }
        }
    }

    /// Switches to the machine's new time zone. Foundation keeps the zone it read
    /// first, so it forgets that one before.
    private func followSystemTimeZone() {
        NSTimeZone.resetSystemTimeZone()
        switchTimeZone(to: .current)
    }

    /// Counts study days in `timeZone` from now on, starting them at the same hour.
    /// Running sessions follow, as they get the calendar with every review.
    func switchTimeZone(to timeZone: TimeZone) {
        guard timeZone != calendar.timeZone else { return }
        calendar.timeZone = timeZone
    }

    /// The error to show when reading a deck failed with `error`. A deck the app
    /// rejects can't be opened at all, so the message says what is wrong with it: the
    /// learner may restore a backup or repair the file by hand.
    nonisolated static func openingError(for error: Error) -> Error {
        guard let error = error as? DeckFile.Error else {
            return CocoaError(.fileReadCorruptFile, userInfo: [NSUnderlyingErrorKey: error as NSError])
        }
        switch error {
        case .notADeck:
            return AppError(String(localized: "This file is not a MacVocTrain deck, or its deck.json is missing or damaged."))
        case .unsupportedVersion:
            return AppError(String(localized: "This deck was created by a newer version of MacVocTrain."))
        case .outdatedVersion:
            return AppError(String(localized: "This deck was saved by a test version of MacVocTrain from before its first release and can no longer be opened."))
        case let .damagedReviewLog(line):
            return AppError(String(localized: "The review log of this deck is damaged (line \(line))."))
        case .missingReviewLog:
            return AppError(String(localized: "The review log of this deck (reviews.jsonl) is missing, although some of its cards have been studied."))
        case let .reviewsOfUnknownCard(line):
            return AppError(String(localized: "The review log of this deck contains reviews of a card that is not in the deck (line \(line))."))
        case let .reviewLogTooLong(question):
            return AppError(String(localized: "The review log of the card “\(question)” lists more reviews than the card has had."))
        case let .duplicateCardID(question):
            return AppError(String(localized: "Several cards of this deck have the same ID, among them “\(question)”."))
        case let .parameterOutOfRange(index):
            return AppError(String(localized: "The algorithm parameter w\(index) of this deck is outside its range."))
        }
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
    func add(_ text: CardText) -> Card.ID {
        let card = Card(text: text, created: clock.now)
        if let change = DeckChange.adding([card], to: deck) {
            perform(change, actionName: String(localized: "Add Card"))
        }
        return card.id
    }

    /// Appends cards from an import as one change, see `DeckChange.adding(_:to:)`.
    func importCards(_ cards: [Card]) {
        guard let change = DeckChange.adding(cards, to: deck) else { return }
        perform(change, actionName: String(localized: "Import Cards"))
    }

    /// Changes question, answer and hint of a card, see `DeckChange.editingText(of:to:in:)`.
    func editText(of id: Card.ID, to text: CardText) {
        guard let change = DeckChange.editingText(of: id, to: text, in: deck) else { return }
        perform(change, actionName: String(localized: "Edit Card"))
    }

    func delete(_ ids: Set<Card.ID>) {
        guard let change = DeckChange.removing(ids, from: deck) else { return }
        let name = ids.count == 1 ? String(localized: "Delete Card") : String(localized: "Delete Cards")
        perform(change, actionName: name)
    }

    func resetLearningState(of ids: Set<Card.ID>) {
        guard let change = DeckChange.resettingLearningState(of: ids, in: deck) else { return }
        perform(change, actionName: String(localized: "Reset Learning State"))
    }

    /// Stores a card rescheduled after a review in a study session, with the change
    /// `SessionMode.grade(_:in:at:calendar:)` returns. Undo and redo of the review run
    /// `companion` right after the card, in the same undo action; the session brings
    /// back its place with it, see `SessionViewModel.grade`.
    func applyReview(_ change: DeckChange, alongside companion: UndoCompanion) {
        perform(change, actionName: String(localized: "Review"), alongside: companion)
    }

    /// Changes the learning options, see `DeckChange.changingLearningOptions(_:in:calendar:)`.
    func updateLearningOptions(_ learningOptions: LearningOptions) {
        guard let change = DeckChange.changingLearningOptions(learningOptions, in: deck, calendar: calendar) else { return }
        perform(change, actionName: String(localized: "Change Learning Options"))
    }

    /// Merges other versions of the deck into it, in turn, as one undo action, see
    /// `DeckChange.merging(_:into:calendar:)`. Returns whether the deck changed.
    ///
    /// Groups its undo action itself: it runs outside of events too, when the file
    /// changed, and closing the group is what tells SwiftUI of the change.
    @discardableResult
    func merge(_ versions: [Deck]) -> Bool {
        var merged = deck
        var changes: [DeckChange] = []
        for version in versions {
            guard let change = DeckChange.merging(version, into: merged, calendar: calendar) else { continue }
            _ = merged.apply(change, at: clock.now, calendar: calendar)
            changes.append(change)
        }
        guard !changes.isEmpty else { return false }
        undoManager?.beginUndoGrouping()
        perform(changes, actionName: String(localized: "Merge Versions"))
        undoManager?.endUndoGrouping()
        return true
    }

    // MARK: - Undo machinery

    private func perform(_ change: DeckChange, actionName: String, alongside companion: UndoCompanion? = nil) {
        perform([change], actionName: actionName, alongside: companion)
    }

    /// Applies `changes` in turn and registers their inverses as one undo action with
    /// `undoManager`. The undo action runs `companion` once the deck holds the inverses;
    /// the redo action it registers runs the companion reversed.
    ///
    /// Without an undo manager the change could not be undone, and SwiftUI would not
    /// learn of it: autosave might never write it. Debug builds stop there; the released
    /// app still changes the deck.
    private func perform(_ changes: [DeckChange], actionName: String, alongside companion: UndoCompanion? = nil) {
        assert(undoManager != nil, "The document changes without an undo manager; DocumentView sets it.")
        var deck = deck
        let inverses = changes.map { deck.apply($0, at: clock.now, calendar: calendar) }
        self.deck = deck
        undoManager?.registerMainActorUndo(withTarget: self, actionName: actionName) { document, _ in
            document.perform(Array(inverses.reversed()), actionName: actionName, alongside: companion?.reversed)
            companion?.undo()
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
