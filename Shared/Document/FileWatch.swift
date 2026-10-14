import Foundation

/// Hears of changes to the file of an open deck by another process, for
/// `VersionMerger` (#252, #298): connects a `DeckVersionStore` for the file while it
/// can be changed and the app isn't in the background, and reports each change once
/// a short delay has passed.
@MainActor
final class FileWatch {
    /// Runs after the file changed, once `checkDelay` has passed without another change.
    var onChange: (@MainActor () -> Void)?
    /// The file watched, if any; `nil` while it can't be changed.
    private(set) var url: URL?
    /// The store of `url`; `nil` while there is none or the app is in the background.
    private(set) var store: (any DeckVersionStore)?
    /// The report scheduled after the file changed.
    private(set) var checking: Task<Void, Never>?
    /// Whether the app is in the background, see `suspend()`.
    private(set) var isSuspended = false
    private let makeStore: @MainActor (URL, @escaping @MainActor @Sendable () -> Void) -> any DeckVersionStore
    /// How long a report waits after the file changed. During a write by another
    /// process, asking the NSDocument would wait for that process, while it may wait
    /// for this one (#246): the store only learns of the change, the merge comes later.
    private let checkDelay: Duration

    /// - Parameter makeStore: Connects to the file at the URL, with the handler for its
    ///   changes.
    init(checkDelay: Duration, makeStore: @escaping @MainActor (URL, @escaping @MainActor @Sendable () -> Void) -> any DeckVersionStore) {
        self.checkDelay = checkDelay
        self.makeStore = makeStore
    }

    /// Watches the file at `url` from now on, or none if it is `nil`.
    func connect(_ url: URL?) {
        self.url = url
        connectStore()
    }

    /// Lets go of the file when the iPhone app goes to the background: a file presenter
    /// of a suspended app may hold up the other processes that want the file (#246).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        checking?.cancel()
        store = nil
    }

    /// Hears of changes to the file again when the app comes back.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        connectStore()
    }

    private func connectStore() {
        store = nil
        if let url, !isSuspended {
            store = makeStore(url) { [weak self] in self?.fileDidChange() }
        }
    }

    private func fileDidChange() {
        checking?.cancel()
        checking = Task { [weak self, checkDelay] in
            try? await Task.sleep(for: checkDelay)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
