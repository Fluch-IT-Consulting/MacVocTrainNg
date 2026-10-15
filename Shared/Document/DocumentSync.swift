import SwiftUI

extension View {
    /// Wires the view of an open deck to its document and to the `VersionMerger` of the
    /// window or scene: `DocumentView` on the Mac, `DeckView` on the iPhone (#267).
    ///
    /// - Attaches the document to the merger when the view appears, and again when the
    ///   document becomes ready to edit, or the file or whether it can be changed
    ///   changes. The merger waits until the document `isReadyToEdit` (#305): on the
    ///   Mac, the document's view attaches the undo manager, see
    ///   `attachingUndoManager(to:)`; on the iPhone, `OpenDeck` attaches it before it
    ///   shows the document.
    /// - Tells the merger whether a study session is under way.
    ///
    /// - Parameters:
    ///   - fileURL: Where the document is saved; `nil` until it is saved for the first
    ///     time.
    ///   - isEditable: `false` while the deck can only be viewed.
    ///   - isInSession: Whether the view shows a study session.
    func documentSync(_ document: VocabularyDocument, fileURL: URL?, isEditable: Bool, merger: VersionMerger, isInSession: Bool) -> some View {
        modifier(DocumentSync(document: document, isReadyToEdit: document.isReadyToEdit, fileURL: fileURL, isEditable: isEditable, merger: merger, isInSession: isInSession))
    }
}

private struct DocumentSync: ViewModifier {
    var document: VocabularyDocument
    /// Read by the view that observes the document, so a change reaches the modifier.
    var isReadyToEdit: Bool
    var fileURL: URL?
    var isEditable: Bool
    var merger: VersionMerger
    var isInSession: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isReadyToEdit, initial: true, attachToMerger)
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
