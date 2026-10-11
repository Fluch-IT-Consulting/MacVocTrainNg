import Foundation
import Observation

/// A deck the app has opened, as the start screen lists it (#288).
struct KnownDeck: Identifiable, Hashable {
    let url: URL

    var id: URL { url }

    /// The name of the deck, without the extension.
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// The decks the app has opened, which the start screen lists (#288); the one opened
/// last opens again at the next launch (#282, #285).
///
/// Kept as bookmarks in the user defaults: a deck on iCloud Drive lies outside the
/// app's sandbox, and only a bookmark keeps the access the file picker granted to it.
/// Forgetting a deck leaves its file alone.
@MainActor @Observable
final class KnownDecks {
    static let key = "KnownDecks"

    /// The opened last first.
    private var entries: [Entry]
    @ObservationIgnored private let defaults: UserDefaults

    private struct Entry {
        var deck: KnownDeck
        var bookmark: Data
    }

    /// Reads the decks from `defaults`. Forgets those that are gone, e.g. deleted.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = (defaults.array(forKey: Self.key) as? [Data] ?? []).compactMap { bookmark in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
            return Entry(deck: KnownDeck(url: url), bookmark: isStale ? Self.bookmark(for: url) ?? bookmark : bookmark)
        }
        save()
    }

    /// The decks by name, as the start screen lists them.
    var byName: [KnownDeck] {
        entries.map(\.deck).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The deck opened last.
    var last: URL? {
        entries.first?.deck.url
    }

    /// Adds the deck that is open now, or moves it to the front.
    func remember(_ url: URL) {
        guard let bookmark = Self.bookmark(for: url) else { return }
        removeEntry(for: url)
        entries.insert(Entry(deck: KnownDeck(url: url), bookmark: bookmark), at: 0)
        save()
    }

    func forget(_ url: URL) {
        removeEntry(for: url)
        save()
    }

    private func removeEntry(for url: URL) {
        entries.removeAll { FileVersionStore.isSameFile($0.deck.url, url) }
    }

    private func save() {
        defaults.set(entries.map(\.bookmark), forKey: Self.key)
    }

    private static func bookmark(for url: URL) -> Data? {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
