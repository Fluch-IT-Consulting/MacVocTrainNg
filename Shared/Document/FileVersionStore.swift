import Foundation
import VocabCore

/// The file of an open deck: its versions in conflict on iCloud Drive, and the
/// document that saves it. Each app saves its own way and passes that as `Save`: the
/// Mac through the NSDocument behind `DocumentGroup` (`DocumentWindow`), the iPhone
/// through its own UIDocument (`OpenDeck`, #295).
///
/// Hears of every change to the file by another process through a file presenter of
/// its own, next to the document's. The Mac's sandbox allows it with the entitlement
/// for files the learner chose (#246); on the iPhone, the learner chose the file in
/// the file picker.
@MainActor
final class FileVersionStore: DeckVersionStore {
    /// Writes the deck of the document open at the URL to its file now, even if the
    /// document hasn't counted the change yet. Throws if it can't, also if it finds no
    /// document to write, rather than return as if it had saved (#265).
    typealias Save = @MainActor (URL) async throws -> Void

    let url: URL
    private let saveFile: Save
    private let presenter: Presenter

    /// - Parameter onChange: Runs on the main actor after another process changed the
    ///   file or iCloud Drive set a version in conflict aside.
    init(url: URL, save: @escaping Save, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.url = url
        saveFile = save
        presenter = Presenter(url: url, onChange: onChange)
        NSFileCoordinator.addFilePresenter(presenter)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    func save() async throws {
        try await saveFile(url)
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
