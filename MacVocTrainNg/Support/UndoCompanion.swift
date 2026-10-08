/// Something outside the deck that undo and redo of a change to the deck take back
/// and bring again, like the place of a study session after a review. The document
/// runs it in the same undo action as the change, right after the deck, see
/// `VocabularyDocument.applyReview(_:alongside:)`.
struct UndoCompanion: Sendable {
    /// Runs on undo.
    var undo: @MainActor () -> Void
    /// Runs on redo.
    var redo: @MainActor () -> Void

    /// The companion of the opposite step: what redo ran, undo runs, and vice versa.
    var reversed: UndoCompanion { UndoCompanion(undo: redo, redo: undo) }
}
