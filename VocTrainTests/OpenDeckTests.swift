import Foundation
import Testing
import VocabCore

@testable import VocTrain

/// Opening, saving and reading again a deck with the app's own UIDocument (#285).
/// A test that waits for the UIDocument in vain fails after a minute instead of
/// holding up the run.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct OpenDeckTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func opensTheDeckOfItsFile() async throws {
        let url = try write(Deck(cards: [makeCard("dom")]))
        let deck = OpenDeck(url: url)

        let document = try await waitForDocument(of: deck)
        #expect(document.deck.cards.map(\.question) == ["dom"])
        #expect(deck.isEditable)
        await deck.close()
    }

    @Test func aFileThatIsNoDeckFails() async throws {
        let url = directory.appending(path: "Broken.voctrain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let deck = OpenDeck(url: url)

        try await wait { deck.failure != nil }
        #expect(deck.document == nil)
        await deck.close()
    }

    /// The UIDocument counts the review through its undo manager and saves it when
    /// the deck closes.
    @Test func closingSavesAReview() async throws {
        let url = try write(Deck(cards: [makeCard("dom")]))
        let deck = OpenDeck(url: url)
        let document = try await waitForDocument(of: deck)
        document.undoManager = deck.undoManager

        review(document)
        // Lets the run loop close the undo group, which the UIDocument counts.
        try await Task.sleep(for: .milliseconds(200))
        await deck.close()

        let saved = try DeckFile.decode(FileWrapper(url: url, options: .immediate))
        #expect(saved.cards.first?.log.map(\.grade) == [.good])
    }

    /// The merger saves through the deck's UIDocument, even a change the UIDocument
    /// hasn't counted (#295): here the change registers with an undo manager of its own.
    @Test func theMergerSavesThroughTheDeckFile() async throws {
        let url = try write(Deck(cards: [makeCard("dom")]))
        let deck = OpenDeck(url: url)
        let document = try await waitForDocument(of: deck)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        document.undoManager = undoManager
        deck.merger.attach(document, fileURL: url, isEditable: true)
        await deck.merger.merging?.value

        undoManager.beginUndoGrouping()
        review(document)
        undoManager.endUndoGrouping()
        // Saves the change at once instead of after a few seconds.
        deck.merger.suspend()
        await deck.merger.saves.saving?.value

        let saved = try DeckFile.decode(FileWrapper(url: url, options: .immediate))
        #expect(saved.cards.first?.log.map(\.grade) == [.good])
        await deck.close()
    }

    /// Another device's change to the file is merged into the open document (#296).
    @Test func aChangedFileIsMergedIntoTheOpenDocument() async throws {
        let dom = makeCard("dom")
        let url = try write(Deck(cards: [dom]))
        let deck = OpenDeck(url: url)
        let document = try await waitForDocument(of: deck)

        try await writeCoordinated(Deck(cards: [dom, makeCard("kot")], contentModified: .now), to: url)

        try await wait { document.deck.cards.count == 2 }
        #expect(document.deck.cards.count == 2)
        #expect(deck.document === document)
        await deck.close()
    }

    /// A study session goes on when the Mac changes the file (#296): the deck gets the
    /// Mac's reviews, and the session skips a card the Mac suspended.
    @Test func aStudySessionGoesOnWhenTheFileChanges() async throws {
        let original = Deck(cards: ["dom", "kot", "pies"].map(makeCard))
        let url = try write(original)
        let deck = OpenDeck(url: url)
        let document = try await waitForDocument(of: deck)
        let model = StudyModel(document: document)
        let asked = try #require(model.currentCard?.id)

        // The Mac reviews one of the cards not asked yet and suspends the other.
        var mac = original
        let notAsked = mac.cards.map(\.id).filter { $0 != asked }
        review(notAsked[0], in: &mac, calendar: document.calendar)
        let suspension = try #require(DeckChange.settingSuspended(true, of: [notAsked[1]], in: mac, at: .now))
        _ = mac.apply(suspension, at: .now, calendar: document.calendar)
        try await writeCoordinated(mac, to: url)

        try await wait { document.deck.card(withID: notAsked[1])?.isSuspended == true }
        #expect(deck.document === document)
        #expect(document.deck.card(withID: notAsked[1])?.isSuspended == true)
        #expect(document.deck.card(withID: notAsked[0])?.log.count == 1)
        #expect(model.currentCard?.id == asked)

        model.reveal()
        model.grade(.good)
        #expect(model.currentCard?.id == notAsked[0])
        await deck.close()
    }

    /// Reviews the first card due with Good, as a study session does.
    private func review(_ document: VocabularyDocument) {
        var mode = SessionMode.study(StudySession(deck: document.deck, at: document.clock.now, calendar: document.calendar))
        guard case let .rescheduled(change) = mode.grade(.good, in: document.deck, at: document.clock.now, calendar: document.calendar) else {
            Issue.record("The study session didn't reschedule the card.")
            return
        }
        document.applyReview(change, alongside: UndoCompanion(undo: {}, redo: {}))
    }

    /// Reviews the card `id` with Good, as the Mac does.
    private func review(_ id: Card.ID, in deck: inout Deck, calendar: StudyCalendar) {
        guard let card = deck.card(withID: id) else { return }
        var mode = SessionMode.study(StudySession(deck: Deck(cards: [card]), at: .now, calendar: calendar))
        guard case let .rescheduled(change) = mode.grade(.good, in: deck, at: .now, calendar: calendar) else {
            Issue.record("The study session didn't reschedule the card.")
            return
        }
        _ = deck.apply(change, at: .now, calendar: calendar)
    }

    private func makeCard(_ question: String) -> Card {
        Card(text: CardText(question: question, answer: "x")!, created: .now.addingTimeInterval(-60))
    }

    private func write(_ deck: Deck) throws -> URL {
        let url = directory.appending(path: "Polish.voctrain", directoryHint: .isDirectory)
        try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    /// Writes `deck` to `url` as another process would, coordinated and off the main
    /// thread: the UIDocument, a file presenter, gives the file up for the write on the
    /// main thread, so a coordinated write there would wait for itself.
    private func writeCoordinated(_ deck: Deck, to url: URL) async throws {
        try await Task.detached {
            var coordinationError: NSError?
            var writeError: (any Error)?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
                do {
                    try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
                } catch {
                    writeError = error
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            if let writeError {
                throw writeError
            }
        }.value
    }

    private func waitForDocument(of deck: OpenDeck) async throws -> VocabularyDocument {
        try await wait { deck.document != nil && deck.isEditable }
        return try #require(deck.document)
    }

    /// Waits up to ten seconds for `condition`.
    private func wait(for condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
