import AppKit
import Testing

/// Tests that show views in real windows. They run one at a time: while one window
/// closes, another one becomes key, and its views may change the focus.
@Suite(.serialized)
enum WindowTests {}

/// Lets SwiftUI update the windows until `condition` holds, at most for `timeout`.
/// Suspends instead of running the run loop nested, so work the views hand to the
/// main actor gets its turn as well.
@MainActor
func waitUntil(
    _ comment: Comment,
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "Timed out waiting until \(comment)", sourceLocation: sourceLocation)
}

/// Gives the window the undo manager a document window gets from its document.
@MainActor
final class DocumentWindowDelegate: NSObject, NSWindowDelegate {
    let undoManager: UndoManager

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }
}
