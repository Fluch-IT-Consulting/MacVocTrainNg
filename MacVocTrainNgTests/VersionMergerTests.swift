import Foundation
import Testing

@testable import MacVocTrain
@testable import VocabCore

/// Merging the versions of a deck that another device changed on iCloud Drive (#252).
@MainActor
struct VersionMergerTests {
    let url = URL(fileURLWithPath: "/Users/learner/Library/Mobile Documents/com~apple~CloudDocs/Polish.voctrain")
    /// 2026-10-05 18:00 in Berlin.
    let start = Date(timeIntervalSince1970: 1_791_216_000)
    let dom = Card(question: "dom", answer: "Haus")
    let kot = Card(question: "kot", answer: "Katze")
    let store = FakeVersionStore()
    /// The undo managers of the documents opened, which the documents hold weakly.
    private let undoManagers = UndoManagers()

    var base: Deck { Deck(cards: [dom, kot]) }

    func day(_ days: Double) -> Date {
        start.addingTimeInterval(days * 86400)
    }

    func makeMerger() -> VersionMerger {
        VersionMerger(saveDelay: .zero, checkDelay: .zero) { [store] _, onChange in
            store.onChange = onChange
            return store
        }
    }

    /// A document as NSDocument reads it from the file, with its undo manager.
    func open(_ deck: Deck) -> (VocabularyDocument, UndoManager) {
        let document = VocabularyDocument(deck: deck, clock: ManualClock(day(5)).studyClock, calendar: .testing)
        let undoManager = makeUndoManager(for: document)
        undoManagers.all.append(undoManager)
        return (document, undoManager)
    }

    /// The change a review with Good on another device makes.
    func review(of card: Card, in deck: Deck, at date: Date) -> DeckChange {
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: .testing)
        var random = Scheduler.random(forReviewOf: card.id, at: date)
        let reviewed = scheduler.review(deck.card(withID: card.id)!, grade: .good, at: date, mode: .revealed, using: &random)
        return DeckChange(upserts: [reviewed], contentStamp: .keep)
    }

    func reviewing(_ card: Card, in deck: Deck, at date: Date) -> Deck {
        var deck = deck
        _ = deck.apply(review(of: card, in: deck, at: date), at: date, calendar: .testing)
        return deck
    }

    /// Reviews like a study session on this Mac.
    func study(_ card: Card, in document: VocabularyDocument, _ undoManager: UndoManager) {
        let change = review(of: card, in: document.deck, at: day(5))
        step(undoManager) { document.applyReview(change, alongside: UndoCompanion(undo: {}, redo: {})) }
    }

    @Test func conflictsAreMergedSavedAndThenResolved() async {
        let mac = reviewing(dom, in: base, at: day(1))
        let conflicts = [
            FakeConflict(deck: reviewing(kot, in: base, at: day(2)), store: store),
            FakeConflict(deck: reviewing(dom, in: base, at: day(3)), store: store),
        ]
        store.conflicts = conflicts
        let (document, undoManager) = open(mac)
        let merger = makeMerger()

        merger.attach(document, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(document.deck.cards.map(\.log.count) == [2, 1])
        #expect(conflicts.allSatisfy { $0.isResolved })
        #expect(Array(store.events.prefix(3)) == ["save", "resolve", "resolve"])
        #expect(undoManager.undoActionName == "Merge Versions" || undoManager.undoActionName == "Fassungen zusammenführen")

        undoManager.undo()
        #expect(document.deck.cards == mac.cards)
        #expect(!undoManager.canUndo)
    }

    @Test func conflictsHeldAlreadyAreResolvedWithoutSaving() async {
        let mac = reviewing(dom, in: base, at: day(1))
        let conflict = FakeConflict(deck: base, store: store)
        store.conflicts = [conflict]
        let (document, undoManager) = open(mac)
        let merger = makeMerger()

        merger.attach(document, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(conflict.isResolved)
        #expect(store.events == ["resolve"])
        #expect(!undoManager.canUndo)
    }

    @Test func aConflictThatCantBeReadStaysAndIsReportedOnce() async {
        let conflict = FakeConflict(deck: nil, store: store)
        store.conflicts = [conflict]
        let (document, _) = open(base)
        let merger = makeMerger()

        merger.attach(document, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(!conflict.isResolved)
        #expect(merger.failure != nil)

        merger.failure = nil
        await merger.mergeVersions().value
        #expect(merger.failure == nil)
        #expect(!conflict.isResolved)
    }

    @Test func aChangedFileIsMergedAfterItsConflicts() async {
        let (document, _) = open(base)
        let merger = makeMerger()
        merger.attach(document, fileURL: url, isEditable: true)
        await merger.merging?.value

        // iCloud Drive kept this Mac's version and set the other device's aside.
        store.conflicts = [FakeConflict(deck: reviewing(kot, in: base, at: day(2)), store: store)]
        store.onChange?()
        await merger.checking?.value
        await merger.merging?.value
        #expect(document.deck.card(withID: kot.id)?.log.count == 1)
        #expect(store.conflicts.allSatisfy { $0.isResolved })
    }

    /// NSDocument reads the file again after another device changed it, and sets the
    /// changes it hadn't saved yet aside.
    @Test func unsavedChangesSurviveReadingTheFileAgain() async {
        let merger = makeMerger()
        let (before, undoManagerBefore) = open(base)
        merger.attach(before, fileURL: url, isEditable: true)
        await merger.merging?.value
        study(dom, in: before, undoManagerBefore)

        let (reread, _) = open(reviewing(kot, in: base, at: day(2)))
        merger.attach(reread, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(reread.deck.cards.map(\.log.count) == [1, 1])
        #expect(!merger.endedSession)
    }

    @Test func readingTheFileAgainEndsTheStudySession() async {
        let merger = makeMerger()
        let (before, undoManagerBefore) = open(base)
        merger.attach(before, fileURL: url, isEditable: true)
        merger.isInSession = true
        study(dom, in: before, undoManagerBefore)

        let (reread, _) = open(reviewing(kot, in: base, at: day(2)))
        merger.attach(reread, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(merger.endedSession)
        #expect(!merger.isInSession)
        #expect(reread.deck.card(withID: dom.id)?.log.count == 1)
    }

    /// Reverting to the saved or an older version reads a file that holds nothing new.
    @Test func revertingKeepsTheVersionRead() async {
        let merger = makeMerger()
        let (before, undoManagerBefore) = open(base)
        merger.attach(before, fileURL: url, isEditable: true)
        merger.isInSession = true
        study(dom, in: before, undoManagerBefore)

        let (reverted, undoManager) = open(base)
        merger.attach(reverted, fileURL: url, isEditable: true)
        await merger.merging?.value
        #expect(reverted.deck.cards == base.cards)
        #expect(!undoManager.canUndo)
        #expect(!merger.endedSession)
    }

    @Test func everyChangeIsSavedSoon() async {
        let (document, undoManager) = open(base)
        let merger = makeMerger()
        merger.attach(document, fileURL: url, isEditable: true)
        await merger.merging?.value

        study(dom, in: document, undoManager)
        await merger.saving?.value
        #expect(store.events == ["save"])
    }

    /// E.g. an old version in the version browser, or a new deck not saved yet.
    @Test(arguments: [true, false])
    func aDeckThatCantChangeOrHasNoFileIsLeftAlone(isEditable: Bool) async {
        let conflict = FakeConflict(deck: reviewing(kot, in: base, at: day(2)), store: store)
        store.conflicts = [conflict]
        let (document, undoManager) = open(base)
        let merger = makeMerger()

        merger.attach(document, fileURL: isEditable ? nil : url, isEditable: isEditable)
        await merger.merging?.value
        if isEditable {
            step(undoManager) { document.add(CardText(question: "pies", answer: "Hund")!) }
        }
        await merger.saving?.value
        #expect(store.onChange == nil)
        #expect(!conflict.isResolved)
        #expect(store.events.isEmpty)
    }
}

/// Keeps undo managers for as long as a test runs.
@MainActor
private final class UndoManagers {
    var all: [UndoManager] = []
}

/// The file of a deck in a test: no presenter, no NSDocument.
@MainActor
final class FakeVersionStore: DeckVersionStore {
    var conflicts: [FakeConflict] = []
    /// "save" and "resolve", in the order they happened.
    var events: [String] = []
    /// The handler `VersionMerger` gave the store for changes to the file.
    var onChange: (@MainActor @Sendable () -> Void)?

    func unresolvedConflicts() -> [ConflictVersion] {
        conflicts.filter { !$0.isResolved }.map { conflict in
            ConflictVersion(
                id: conflict.id,
                read: {
                    guard let deck = conflict.deck else { throw DeckFile.Error.notADeck }
                    return deck
                },
                markResolved: { conflict.resolve() }
            )
        }
    }

    func save() async throws {
        events.append("save")
    }
}

/// A version in conflict in a test; `deck` is `nil` for one that can't be read.
@MainActor
final class FakeConflict {
    let id = UUID().uuidString
    let deck: Deck?
    private(set) var isResolved = false
    private unowned let store: FakeVersionStore

    init(deck: Deck?, store: FakeVersionStore) {
        self.deck = deck
        self.store = store
    }

    func resolve() {
        isResolved = true
        store.events.append("resolve")
    }
}
