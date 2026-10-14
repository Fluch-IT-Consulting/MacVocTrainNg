import AppKit
import os

extension FileVersionStore {
    /// The error `saveDocument(at:)` throws when it finds no document for the file. It
    /// shouldn't happen: the way the app finds its document broke, perhaps with an
    /// update of the SDK. The merger then keeps the conflicts, and the Mac's log says so.
    struct DocumentNotFound: Error {}

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mfluch.voctrain", category: "FileVersionStore")

    /// How the Mac app saves a deck, see `Save`: in place through the NSDocument behind
    /// `DocumentGroup`, like autosave, even if NSDocument hasn't counted the change yet.
    /// Throws `DocumentNotFound` if there is no document for the file.
    static func saveDocument(at url: URL) async throws {
        guard let document = NSDocumentController.shared.document(for: url), let fileURL = document.fileURL, let fileType = document.fileType else {
            let name = url.lastPathComponent
            logger.error("Found no document to save \(name, privacy: .private)")
            throw DocumentNotFound()
        }
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
}
