import AppKit

extension FileVersionStore {
    /// Saves in place through the NSDocument behind `DocumentGroup`, like autosave, even
    /// if NSDocument hasn't counted the change yet. Throws `DocumentNotFound` if there is
    /// no document for the file.
    func save() async throws {
        guard let document = NSDocumentController.shared.document(for: url), let fileURL = document.fileURL, let fileType = document.fileType else { throw documentNotFound() }
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
