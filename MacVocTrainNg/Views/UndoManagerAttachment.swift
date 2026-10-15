import SwiftUI

extension View {
    /// Attaches the undo manager of the view's environment to `document`, and detaches
    /// it when the environment holds none (#305). SwiftUI creates the document but hands
    /// the undo manager of its NSDocument only to views.
    ///
    /// Belongs on the document's view, not on a view inside a sheet: a sheet's
    /// environment holds the undo manager of the sheet's own window instead (#48).
    func attachingUndoManager(to document: VocabularyDocument) -> some View {
        modifier(UndoManagerAttachment(document: document))
    }
}

private struct UndoManagerAttachment: ViewModifier {
    var document: VocabularyDocument
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .onChange(of: undoManager, initial: true) { _, undoManager in
                document.attachUndoManager(undoManager)
            }
    }
}
