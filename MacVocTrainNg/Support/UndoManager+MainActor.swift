import Foundation

extension UndoManager {
    /// Registers `handler` as the undo action for `target` and names it. The handler
    /// gets the undo manager, so it can register the redo action.
    ///
    /// The undo manager doesn't hold `target`: it must live as long as the undo stack,
    /// like the document. What may go before, the handler reaches weakly.
    ///
    /// Undo handlers run on the main thread, where the undo manager lives. This is
    /// the one place that tells the compiler so.
    @MainActor
    func registerMainActorUndo<Target: AnyObject & Sendable>(
        withTarget target: Target,
        actionName: String,
        handler: @escaping @MainActor (Target, UndoManager) -> Void
    ) {
        nonisolated(unsafe) let undoManager = self
        registerUndo(withTarget: target) { target in
            MainActor.assumeIsolated {
                handler(target, undoManager)
            }
        }
        setActionName(actionName)
    }
}
