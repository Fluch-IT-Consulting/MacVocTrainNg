import Foundation
import Testing
import VocabCore

@testable import VocTrain

/// Remembering the deck shown last (#282, #285).
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

    private func makeDeck(named name: String) throws -> URL {
        let url = directory.appending(path: "\(name).voctrain", directoryHint: .isDirectory)
        try DeckFile.fileWrapper(for: Deck()).write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "LastDeckTests-\(UUID().uuidString)"))
    }
}
