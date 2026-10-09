// SPIKE #246 – throwaway iPhone app, never merged.
//
// Opens a .voctrain package from the Files app / iCloud Drive with DocumentGroup,
// reads it with DeckFile.decode, shows the due count, grades the next due card through
// SessionMode.study and lets UIDocument save it back. The event log at the bottom shows
// what the system reports while the Mac changes the same package.

import SwiftUI
import UniformTypeIdentifiers
import VocabCore

extension UTType {
    static let vocabularyDeck = UTType(exportedAs: "com.mfluch.voctrain.deck", conformingTo: .package)
}

@main
struct VocTrainPhoneApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PhoneDocument() }) { file in
            DeckScreen(document: file.document, fileURL: file.fileURL)
                // As on the Mac: a revert hands the scene a new document.
                .id(ObjectIdentifier(file.document))
        }
    }
}

/// Lines shown at the bottom of every deck screen; survives document replacement.
@MainActor
final class EventLog: ObservableObject {
    static let shared = EventLog()
    @Published private(set) var lines: [String] = []

    nonisolated static func add(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        Task { @MainActor in
            shared.lines.insert("\(stamp) \(line)", at: 0)
            print("spike246: \(line)")
        }
    }
}

final class PhoneDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.vocabularyDeck] }

    @Published var deck: Deck
    private let lock = NSLock()
    private var savedDeck: Deck

    init() {
        let deck = Deck()
        self.deck = deck
        savedDeck = deck
    }

    required init(configuration: ReadConfiguration) throws {
        let deck = try DeckFile.decode(configuration.file)
        self.deck = deck
        savedDeck = deck
        EventLog.add("read: \(deck.cards.count) cards, \(deck.cards.reduce(0) { $0 + $1.log.count }) reviews (\(Thread.isMainThread ? "main" : "bg"))")
    }

    func snapshot(contentType: UTType) throws -> Deck {
        lock.withLock { savedDeck }
    }

    func fileWrapper(snapshot: Deck, configuration: WriteConfiguration) throws -> FileWrapper {
        EventLog.add("write: \(snapshot.cards.count) cards, \(snapshot.cards.reduce(0) { $0 + $1.log.count }) reviews")
        return try DeckFile.fileWrapper(for: snapshot)
    }

    /// Grades the first card a fresh study session would ask. Registers undo, which
    /// is how SwiftUI learns that the document must be saved.
    @MainActor
    func gradeNext(_ grade: Grade, undoManager: UndoManager?) -> String {
        let now = Date()
        let calendar = StudyCalendar()
        var mode = SessionMode.study(StudySession(deck: deck, at: now, calendar: calendar))
        guard let id = mode.session.currentCardID, let question = deck.card(withID: id)?.question else { return "nothing due" }
        guard case let .rescheduled(change) = mode.grade(grade, in: deck, at: now, calendar: calendar) else { return "not graded" }
        var newDeck = deck
        let inverse = newDeck.apply(change, day: calendar.dayNumber(for: now))
        set(newDeck)
        undoManager?.registerUndo(withTarget: self) { document in
            var restored = document.deck
            _ = restored.apply(inverse, day: calendar.dayNumber(for: now))
            MainActor.assumeIsolated { document.set(restored) }
        }
        return "\(question) → \(grade)"
    }

    @MainActor
    private func set(_ newDeck: Deck) {
        deck = newDeck
        lock.withLock { savedDeck = newDeck }
    }
}

struct DeckScreen: View {
    @ObservedObject var document: PhoneDocument
    var fileURL: URL?
    @ObservedObject private var log = EventLog.shared
    @Environment(\.undoManager) private var undoManager
    @State private var presenter: Presenter?

    var body: some View {
        List {
            Section("Deck") {
                LabeledContent("Cards", value: "\(document.deck.cards.count)")
                LabeledContent("Due now", value: "\(document.deck.dueCount(at: Date()))")
                LabeledContent("Reviews", value: "\(document.deck.cards.reduce(0) { $0 + $1.log.count })")
                Text(fileURL?.path ?? "no URL").font(.caption2).foregroundStyle(.secondary)
            }
            Section("Grade next due card") {
                HStack {
                    ForEach([Grade.again, .hard, .good, .easy], id: \.self) { grade in
                        Button("\(grade)") {
                            EventLog.add("grade " + document.gradeNext(grade, undoManager: undoManager))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            Section("Versions") {
                Button("Check conflict versions") { checkVersions() }
            }
            Section("Events") {
                ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
        }
        .task(id: fileURL) {
            EventLog.add("screen for document \(ObjectIdentifier(document).hashValue)")
            guard let fileURL, presenter == nil else { return }
            let presenter = Presenter(url: fileURL)
            NSFileCoordinator.addFilePresenter(presenter)
            self.presenter = presenter
            checkVersions()
        }
        .onDisappear {
            if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        }
    }

    private func checkVersions() {
        guard let fileURL else { return }
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []
        let others = NSFileVersion.otherVersionsOfItem(at: fileURL) ?? []
        EventLog.add("ubiquitous \(FileManager.default.isUbiquitousItem(at: fileURL)), conflicts \(conflicts.count), other versions \(others.count)")
        for version in conflicts {
            let decoded = (try? FileWrapper(url: version.url)).flatMap { try? DeckFile.decode($0) }
            EventLog.add("  conflict from \(version.localizedNameOfSavingComputer ?? "?"): \(decoded.map { "\($0.cards.reduce(0) { $0 + $1.log.count }) reviews" } ?? "does NOT decode")")
        }
    }
}

/// Logs file-coordination callbacks next to UIDocument's own presenter.
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

    func presentedItemDidChange() { EventLog.add("PRESENTER didChange") }
    func presentedItemDidGain(_ version: NSFileVersion) { EventLog.add("PRESENTER didGain conflict=\(version.isConflict)") }
    func presentedItemDidLose(_ version: NSFileVersion) { EventLog.add("PRESENTER didLose") }
    func presentedItemDidResolveConflict(_ version: NSFileVersion) { EventLog.add("PRESENTER didResolveConflict") }
    func presentedItemDidMove(to newURL: URL) { EventLog.add("PRESENTER didMove") }
    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        EventLog.add("PRESENTER writer")
        writer(nil)
    }
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        EventLog.add("PRESENTER deletion")
        completionHandler(nil)
    }
}
