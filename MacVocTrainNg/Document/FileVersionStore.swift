import AppKit
import VocabCore

/// The file of an open deck: its versions in conflict on iCloud Drive, and the
/// NSDocument behind `DocumentGroup`, which saves it.
///
/// Hears of every change to the file by another process through a file presenter of
/// its own, next to the NSDocument's. The sandbox allows it with the entitlement for
/// files the learner chose (#246).
@MainActor
final class FileVersionStore: DeckVersionStore {
    let url: URL
    private let presenter: Presenter

    /// - Parameter onChange: Runs on the main actor after another process changed the
    ///   file or iCloud Drive set a version in conflict aside.
    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.url = url
        presenter = Presenter(url: url, onChange: onChange)
        NSFileCoordinator.addFilePresenter(presenter)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    /// Leaves out versions iCloud Drive hasn't downloaded yet; a later merge gets them.
    func unresolvedConflicts() -> [ConflictVersion] {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        return versions.filter(\.hasLocalContents).map { version in
            ConflictVersion(
                id: version.url.path,
                read: { try DeckFile.decode(FileWrapper(url: version.url, options: .immediate)) },
                markResolved: { version.isResolved = true }
            )
        }
    }

    /// Saves in place, like autosave, even if NSDocument hasn't counted the change yet.
    func save() async throws {
        guard let document = NSDocumentController.shared.document(for: url), let fileURL = document.fileURL, let fileType = document.fileType else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            document.save(to: fileURL, ofType: fileType, for: .autosaveInPlaceOperation) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Only passes events on to the main actor, at once and without waiting: asking the
    /// NSDocument from a callback while another process writes would wait for that
    /// process, which waits for the callback (#246).
    private final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            return queue
        }()
        private let onChange: @MainActor @Sendable () -> Void

        init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
            presentedItemURL = url
            self.onChange = onChange
        }

        func presentedItemDidChange() {
            notify()
        }

        func presentedItemDidGain(_ version: NSFileVersion) {
            notify()
        }

        private func notify() {
            Task { @MainActor [onChange] in onChange() }
        }
    }
}
