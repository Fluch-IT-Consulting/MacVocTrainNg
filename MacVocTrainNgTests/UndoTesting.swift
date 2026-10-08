import Foundation

@testable import MacVocTrain

/// An undo manager that groups explicitly, as there is no event loop in tests, given to
/// `document` like `DocumentView` does in the app. The document holds it weakly, so the
/// test keeps it.
@MainActor
func makeUndoManager(for document: VocabularyDocument) -> UndoManager {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    document.undoManager = undoManager
    return undoManager
}

/// Runs `action` in an undo group of its own, like one event in the app.
@MainActor
func step(_ undoManager: UndoManager, _ action: () -> Void) {
    undoManager.beginUndoGrouping()
    action()
    undoManager.endUndoGrouping()
}
