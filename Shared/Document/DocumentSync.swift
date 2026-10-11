import SwiftUI

extension View {
    /// Wires the view of an open deck to its document and to the `VersionMerger` of the
    /// window or scene: `DocumentView` on the Mac, `DeckView` on the iPhone (#267).
    ///
    /// - Gives the document the undo manager of the view's environment, which SwiftUI
    ///   hands only to views; every change of the document registers there. A sheet's
    ///   environment holds the undo manager of the sheet's own window instead (#48), so
    ///   this belongs on the document's view, not on a view inside a sheet.
    /// - Attaches the document to the merger when the view appears, and again when the
    ///   undo manager, the file or whether it can be changed changes.
    /// - Tells the merger whether a study session is under way.
    ///
    /// - Parameters:
    ///   - fileURL: Where the document is saved; `nil` until it is saved for the first
    ///     time.
    ///   - isEditable: `false` while the deck can only be viewed.
    ///   - isInSession: Whether the view shows a study session.
    func documentSync(_ document: VocabularyDocument, fileURL: URL?, isEditable: Bool, merger: VersionMerger, isInSession: Bool) -> some View {
        modifier(DocumentSync(document: document, fileURL: fileURL, isEditable: isEditable, merger: merger, isInSession: isInSession))
    }
}

private struct DocumentSync: ViewModifier {
    var document: VocabularyDocument
    var fileURL: URL?
    var isEditable: Bool
    var merger: VersionMerger
    var isInSession: Bool
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .onChange(of: undoManager, initial: true) {
                document.undoManager = undoManager
                attachToMerger()
            }
            .onChange(of: fileURL, attachToMerger)
            .onChange(of: isEditable, attachToMerger)
            .onChange(of: isInSession) { _, isInSession in
                merger.isInSession = isInSession
            }
    }

    private func attachToMerger() {
        merger.attach(document, fileURL: fileURL, isEditable: isEditable)
    }
}
