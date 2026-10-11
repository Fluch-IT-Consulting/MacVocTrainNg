import Foundation
import VocabCore
import os

/// The file of an open deck: its versions in conflict on iCloud Drive, and the
/// document behind `DocumentGroup`, which saves it. Each app finds that document its
/// own way: an NSDocument on the Mac, a UIDocument on the iPhone, see `save()` in the
/// extensions of the two apps. If it finds none, `save()` throws rather than return as
/// if it had saved (#265).
///
/// Hears of every change to the file by another process through a file presenter of
/// its own, next to the document's. The Mac's sandbox allows it with the entitlement
/// for files the learner chose (#246); on the iPhone, the learner chose the file in
/// the document browser.
@MainActor
final class FileVersionStore: DeckVersionStore {
    let url: URL
    private let presenter: Presenter
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mfluch.voctrain", category: "FileVersionStore")

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

    /// The error `save()` throws when it finds no document for the file. It shouldn't
    /// happen: the way the app finds the document behind `DocumentGroup` broke, perhaps
    /// with an update of the SDK. The merger then keeps the conflicts, and the device's
    /// log says so.
    struct DocumentNotFound: Error {}

    /// Logs that `save()` found no document for the file, and returns the error to throw.
    func documentNotFound() -> DocumentNotFound {
        let name = url.lastPathComponent
        Self.logger.error("Found no document to save \(name, privacy: .private)")
        return DocumentNotFound()
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

    /// Only passes events on to the main actor, at once and without waiting: asking the
    /// document from a callback while another process writes would wait for that
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
