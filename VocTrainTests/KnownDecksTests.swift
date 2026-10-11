import Foundation
import Testing
import VocabCore

@testable import VocTrain

/// The decks the app has opened (#282, #288).
@MainActor
struct KnownDecksTests {
    let directory: URL
    let defaults: UserDefaults

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try #require(UserDefaults(suiteName: "KnownDecksTests-\(UUID().uuidString)"))
    }

    @Test func rememberedDecksAreListedByNameAfterTheNextLaunch() throws {
        let spanish = try makeDeck(named: "Spanish")
        let polish = try makeDeck(named: "Polish")
        let known = KnownDecks(defaults: defaults)
        known.remember(spanish)
        known.remember(polish)

        #expect(KnownDecks(defaults: defaults).byName.map(\.name) == ["Polish", "Spanish"])
    }

    @Test func theDeckOpenedLastOpensAtLaunch() throws {
        let polish = try makeDeck(named: "Polish")
        let spanish = try makeDeck(named: "Spanish")
        let known = KnownDecks(defaults: defaults)
        known.remember(polish)
        known.remember(spanish)
        known.remember(polish)

        let last = try #require(KnownDecks(defaults: defaults).last)
        #expect(FileVersionStore.isSameFile(last, polish))
        #expect(known.byName.count == 2)
    }

    @Test func aForgottenDeckLeavesTheListButNotTheDisk() throws {
        let url = try makeDeck(named: "Polish")
        let known = KnownDecks(defaults: defaults)
        known.remember(url)
        known.forget(url)

        #expect(KnownDecks(defaults: defaults).byName.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aDeletedDeckIsForgotten() throws {
        let url = try makeDeck(named: "Polish")
        KnownDecks(defaults: defaults).remember(url)
        try FileManager.default.removeItem(at: url)

        #expect(KnownDecks(defaults: defaults).last == nil)
        #expect(defaults.array(forKey: KnownDecks.key)?.isEmpty == true)
    }

    private func makeDeck(named name: String) throws -> URL {
        let url = directory.appending(path: "\(name).voctrain", directoryHint: .isDirectory)
        try DeckFile.fileWrapper(for: Deck()).write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }
}
