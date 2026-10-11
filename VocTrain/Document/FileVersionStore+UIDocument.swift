import UIKit

extension FileVersionStore {
    /// Saves in place through the UIDocument behind `DocumentGroup`, even if it hasn't
    /// counted the change yet. SwiftUI keeps the UIDocument to itself, but it is among
    /// the file presenters of the app. Throws `DocumentNotFound` if it isn't.
    func save() async throws {
        let documents = NSFileCoordinator.filePresenters.compactMap { $0 as? UIDocument }
        guard let document = documents.first(where: { Self.isSameFile($0.fileURL, url) }) else { throw documentNotFound() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            document.save(to: document.fileURL, for: .forOverwriting) { success in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    /// Whether two URLs name the same file, however they spell it: the path of a
    /// package may end with a slash, and `/var` is a link to `/private/var`.
    nonisolated static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
