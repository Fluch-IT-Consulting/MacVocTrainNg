// SPIKE #246 – throwaway diagnostics, never merged.
//
// Logs what happens to an open deck when another process changes its package, e.g.
// iCloud Drive syncing a change from a second device. Read the log with
//
//   log stream --level debug --predicate 'subsystem == "com.mfluch.MacVocTrainNg" AND category == "spike246"'
//
// A second NSFilePresenter on the deck's URL logs every file-coordination callback,
// together with the state of the NSDocument behind SwiftUI's ReferenceFileDocument
// (found via NSDocumentController.shared.document(for:)) and the deck's versions.
//
// Distributed notifications let a shell script drive the app without clicks:
//   com.mfluch.spike246.dump     logs the state of every open deck
//   com.mfluch.spike246.addCard  adds a card to every open deck (makes it dirty)

import AppKit
import SwiftUI
import VocabCore
import os

enum Spike246 {
    static let log = Logger(subsystem: "com.mfluch.MacVocTrainNg", category: "spike246")

    @MainActor private static var presenters: [URL: Presenter] = [:]
    @MainActor private static var documents: [ObjectIdentifier: WeakDocument] = [:]
    @MainActor private static var observing = false

    private struct WeakDocument {
        weak var document: VocabularyDocument?
    }

    /// Called by `DocumentView` whenever its document or file URL changes.
    @MainActor static func attach(_ document: VocabularyDocument, fileURL: URL?) {
        startObservingDistributedNotifications()
        documents[ObjectIdentifier(document)] = WeakDocument(document: document)
        log.notice("view attached: document \(ObjectIdentifier(document).debugDescription, privacy: .public), cards \(document.deck.cards.count), url \(fileURL?.path ?? "nil", privacy: .public)")
        guard let fileURL else { return }
        if presenters[fileURL] == nil {
            let presenter = Presenter(url: fileURL)
            NSFileCoordinator.addFilePresenter(presenter)
            presenters[fileURL] = presenter
            log.notice("own presenter added for \(fileURL.path, privacy: .public)")
        }
        dump(fileURL, reason: "attach")
    }

    @MainActor static func dump(_ url: URL, reason: String) {
        log.notice("— \(reason, privacy: .public) — \(url.lastPathComponent, privacy: .public)")
        if let document = NSDocumentController.shared.document(for: url) {
            let type = type(of: document)
            var chain: [String] = []
            var current: AnyClass? = type
            while let cls = current {
                chain.append(NSStringFromClass(cls))
                current = class_getSuperclass(cls)
            }
            log.notice("  NSDocument: \(chain.joined(separator: " → "), privacy: .public)")
            log.notice("  edited \(document.isDocumentEdited), unautosaved \(document.hasUnautosavedChanges), autosavesInPlace \(type.autosavesInPlace), preservesVersions \(type.preservesVersions), usesUbiquitousStorage \(type.usesUbiquitousStorage)")
            log.notice("  fileModificationDate \(document.fileModificationDate?.description ?? "nil", privacy: .public), on disk \(diskDate(url)?.description ?? "nil", privacy: .public)")
        } else {
            log.notice("  NSDocumentController.shared.document(for:) → nil")
        }
        let ubiquitous = FileManager.default.isUbiquitousItem(at: url)
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        let others = NSFileVersion.otherVersionsOfItem(at: url) ?? []
        log.notice("  ubiquitous \(ubiquitous), unresolved conflicts \(conflicts.count), other versions \(others.count)")
        for version in conflicts {
            log.notice("  conflict: \(version.localizedNameOfSavingComputer ?? "?", privacy: .public) \(version.modificationDate?.description ?? "?", privacy: .public) \(version.url.path, privacy: .public)")
            if let wrapper = try? FileWrapper(url: version.url), let deck = try? DeckFile.decode(wrapper) {
                log.notice("    decodes: \(deck.cards.count) cards, \(deck.cards.reduce(0) { $0 + $1.log.count }) reviews")
            } else {
                log.notice("    does NOT decode / not readable")
            }
        }
        for version in others {
            let decoded = (try? FileWrapper(url: version.url)).flatMap { try? DeckFile.decode($0) }
            log.notice("  other version: \(version.modificationDate?.description ?? "?", privacy: .public) \(decoded.map { "\($0.cards.count) cards" } ?? "does NOT decode", privacy: .public)")
        }
        for (_, entry) in documents {
            guard let document = entry.document else { continue }
            log.notice("  live VocabularyDocument \(ObjectIdentifier(document).debugDescription, privacy: .public): \(document.deck.cards.count) cards, \(document.deck.cards.reduce(0) { $0 + $1.log.count }) reviews")
        }
    }

    private static func diskDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    @MainActor private static func startObservingDistributedNotifications() {
        guard !observing else { return }
        observing = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.mfluch.spike246.dump"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                for url in presenters.keys { dump(url, reason: "dump requested") }
            }
        }
        center.addObserver(forName: .init("com.mfluch.spike246.addCard"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                for (_, entry) in documents {
                    guard let document = entry.document, let text = CardText(question: "spike \(Date())", answer: "x") else { continue }
                    document.add(text)
                    log.notice("added a card to \(ObjectIdentifier(document).debugDescription, privacy: .public)")
                }
                // An undo registration outside a user event doesn't always reach
                // NSDocument's change count; mark the document dirty like a click would.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    for document in NSDocumentController.shared.documents where !document.isDocumentEdited {
                        document.updateChangeCount(.changeDone)
                        log.notice("updateChangeCount(.changeDone) on \(document.fileURL?.lastPathComponent ?? "?", privacy: .public)")
                    }
                }
            }
        }
    }

    /// Logs every callback; does nothing else, so NSDocument's own presenter behaves as without it.
    final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            return queue
        }()

        init(url: URL) {
            presentedItemURL = url
        }

        /// Logs at once, dumps the state 2 s later: during a coordinated write NSDocument
        /// blocks `fileURL` & co. until the writer is done, and the writer waits for us.
        private func event(_ name: String) {
            Spike246.log.notice("PRESENTER \(name, privacy: .public)")
            guard let url = presentedItemURL else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated { Spike246.dump(url, reason: "2 s after \(name)") }
            }
        }

        func presentedItemDidChange() { event("presentedItemDidChange") }
        func presentedSubitemDidChange(at url: URL) { event("presentedSubitemDidChange \(url.lastPathComponent)") }
        func presentedItemDidGain(_ version: NSFileVersion) { event("presentedItemDidGain conflict=\(version.isConflict)") }
        func presentedItemDidLose(_ version: NSFileVersion) { event("presentedItemDidLose") }
        func presentedItemDidResolveConflict(_ version: NSFileVersion) { event("presentedItemDidResolveConflict") }
        func presentedSubitem(at url: URL, didGain version: NSFileVersion) { event("presentedSubitemDidGain \(url.lastPathComponent)") }
        func presentedItemDidMove(to newURL: URL) { event("presentedItemDidMove \(newURL.path)") }
        func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
            event("accommodatePresentedItemDeletion")
            completionHandler(nil)
        }
        func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
            Spike246.log.notice("PRESENTER relinquishPresentedItem(toWriter:) – another process writes")
            writer { Spike246.log.notice("PRESENTER reacquire after writer") }
        }
    }
}
