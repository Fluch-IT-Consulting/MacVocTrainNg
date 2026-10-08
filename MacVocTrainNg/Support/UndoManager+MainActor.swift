import Foundation

extension UndoManager {
    /// Registers `handler` as the undo action for `target` and names it. The handler
    /// gets the undo manager, so it can register the redo action.
    ///
    /// The undo manager doesn't hold `target`: it must live as long as the undo stack,
    /// like the document. What may go before, the handler reaches weakly.
    ///
    /// The action holds the undo manager weakly too: the undo manager holds its
    /// actions, and nothing clears them when the document closes, so a strong
    /// reference would keep both alive until the app quits (#181). The action only
    /// runs while the undo manager runs it.
    ///
    /// Undo handlers run on the main thread, where the undo manager lives. This is
    /// the one place that tells the compiler so.
    @MainActor
    func registerMainActorUndo<Target: AnyObject & Sendable>(
        withTarget target: Target,
        actionName: String,
        handler: @escaping @MainActor (Target, UndoManager) -> Void
    ) {
        nonisolated(unsafe) weak var undoManager = self
        registerUndo(withTarget: target) { target in
            MainActor.assumeIsolated {
                guard let undoManager else { return }
                handler(target, undoManager)
            }
        }
        setActionName(actionName)
    }
}
