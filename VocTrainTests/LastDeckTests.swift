import Foundation
import Testing
import VocabCore

@testable import VocTrain

/// Opening the deck shown last at launch (#282).
@MainActor
struct LastDeckTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func aRememberedDeckIsFoundAgain() throws {
        let url = try makeDeck(named: "Polish")
        let defaults = try makeDefaults()
        LastDeck(defaults: defaults).remember(url)

        let found = try #require(LastDeck(defaults: defaults).resolve())
        #expect(FileVersionStore.isSameFile(found, url))
    }

    @Test func theDeckRememberedLastWins() throws {
        let first = try makeDeck(named: "Polish")
        let second = try makeDeck(named: "Spanish")
        let defaults = try makeDefaults()
        let lastDeck = LastDeck(defaults: defaults)
        lastDeck.remember(first)
        lastDeck.remember(second)

        let found = try #require(lastDeck.resolve())
        #expect(FileVersionStore.isSameFile(found, second))
    }

    @Test func aDeletedDeckIsForgotten() throws {
        let url = try makeDeck(named: "Polish")
        let defaults = try makeDefaults()
        let lastDeck = LastDeck(defaults: defaults)
        lastDeck.remember(url)
        try FileManager.default.removeItem(at: url)

        #expect(lastDeck.resolve() == nil)
        #expect(defaults.data(forKey: LastDeck.key) == nil)
    }

    /// The document browser of the app hosting the tests takes the deck, and the deck
    /// screen shows it: it remembers the deck then. Tells whether SwiftUI still builds
    /// the browser the way `DocumentBrowser` expects.
    @Test func theDocumentBrowserOpensADeck() async throws {
        let url = try makeDeck(named: "Polish")
        let lastDeck = LastDeck()
        let previous = UserDefaults.standard.data(forKey: LastDeck.key)
        defer {
            UserDefaults.standard.set(previous, forKey: LastDeck.key)
        }
        lastDeck.forget()
        try await wait { !DocumentBrowser.all().isEmpty }
        try #require(!DocumentBrowser.hasOpenDocument)

        try #require(DocumentBrowser.open(url))

        try await wait { lastDeck.resolve() != nil }
        let shown = try #require(lastDeck.resolve())
        #expect(FileVersionStore.isSameFile(shown, url))
    }

    private func makeDeck(named name: String) throws -> URL {
        let url = directory.appending(path: "\(name).voctrain", directoryHint: .isDirectory)
        try DeckFile.fileWrapper(for: Deck()).write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "LastDeckTests-\(UUID().uuidString)"))
    }

    /// Waits up to ten seconds for `condition`.
    private func wait(for condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
