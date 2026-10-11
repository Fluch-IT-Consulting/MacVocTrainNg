import Foundation

/// The deck the app showed last, which it opens again at the next launch (#282).
///
/// Kept as a bookmark in the user defaults: a deck on iCloud Drive lies outside the
/// app's sandbox, and only a bookmark keeps the access the document browser granted to
/// it.
struct LastDeck {
    var defaults: UserDefaults = .standard

    static let key = "LastDeck"

    /// Remembers the file of the deck that is open now; forgets the one before even if
    /// there is no bookmark for this one.
    func remember(_ url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: Self.key)
        } else {
            forget()
        }
    }

    func forget() {
        defaults.removeObject(forKey: Self.key)
    }

    /// The file of the deck remembered last, `nil` if there is none or it is gone, e.g.
    /// deleted; then it is also forgotten.
    func resolve() -> URL? {
        guard let bookmark = defaults.data(forKey: Self.key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            forget()
            return nil
        }
        if isStale {
            remember(url)
        }
        return url
    }

    /// Opens the deck remembered last, once the scene shows its document browser. Not if
    /// a document is open already, e.g. one opened from the Files app or restored by
    /// the system.
    ///
    /// Waits until the browser has come on screen and a moment longer, see
    /// `DocumentBrowser.isOnScreen`; after five seconds without it, opens all the same.
    ///
    /// The deck is forgotten before it opens: the deck screen remembers it again once it
    /// shows it, so a deck that can't be opened isn't tried at every launch.
    @MainActor func reopen() async {
        var attempts = 0
        while !DocumentBrowser.isOnScreen, attempts < 50 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !DocumentBrowser.hasOpenDocument, let url = resolve() else { return }
        // The access lasts as long as the app runs: the document may need it until it
        // closes, and SwiftUI doesn't say when that is.
        let isAccessing = url.startAccessingSecurityScopedResource()
        forget()
        if !DocumentBrowser.open(url) {
            remember(url)
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
