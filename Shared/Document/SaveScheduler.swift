import Foundation

/// Saves a few seconds after every change of a deck, for `VersionMerger` (#252, #298),
/// so the other device gets reviews soon and conflicts become rare. The devices take
/// turns rather than being used at the same time, and iCloud Drive takes about a
/// minute to bring a version over, so waiting a few seconds for more changes costs
/// little.
@MainActor
final class SaveScheduler {
    /// The save scheduled after the latest change, or the one `flush()` started.
    private(set) var saving: Task<Void, Never>?
    /// Whether a change waits for the save scheduled after it.
    private var hasUnsavedChange = false
    /// How long a save waits for more changes.
    private let delay: Duration
    private let save: @MainActor () -> Task<Void, Never>?

    /// - Parameter save: Starts to save the deck and returns the task that saves it, or
    ///   `nil` if there is nowhere to save it now. It decides where at once, when it is
    ///   called.
    init(delay: Duration, save: @escaping @MainActor () -> Task<Void, Never>?) {
        self.delay = delay
        self.save = save
    }

    /// Saves after `delay`, unless another change comes first; then after that one.
    func changed() {
        saving?.cancel()
        hasUnsavedChange = true
        saving = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            hasUnsavedChange = false
            await save()?.value
        }
    }

    /// Saves a change that waits for its save at once, e.g. before the iPhone app goes
    /// to the background.
    func flush() {
        guard hasUnsavedChange else { return }
        saving?.cancel()
        hasUnsavedChange = false
        saving = save()
    }
}
