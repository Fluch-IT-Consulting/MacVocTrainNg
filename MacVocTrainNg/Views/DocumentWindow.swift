import SwiftUI

/// The content of a document window, for as long as the window is open.
///
/// SwiftUI hands the window a new document when NSDocument reads the file again, e.g.
/// on reverting to a saved version or when another device changed it. The content then
/// starts afresh with a `DocumentView` of its own: a session or sheet would go on
/// changing the old document, which nobody saves. The `VersionMerger` stays, so it can
/// keep what the old document held that the file lacks.
struct DocumentWindow: View {
    var file: ReferenceFileDocumentConfiguration<VocabularyDocument>
    @State private var merger = VersionMerger()

    var body: some View {
        DocumentView(document: file.document, fileURL: file.fileURL, isEditable: file.isEditable, merger: merger)
            .id(ObjectIdentifier(file.document))
            .alert("The study session has ended", isPresented: $merger.endedSession) {
            } message: {
                Text("The deck was changed on another device and opened anew. The reviews of the session are kept.")
            }
            .alert("Another version of this deck could not be merged", isPresented: isShowingFailure, presenting: merger.failure) { _ in
            } message: { failure in
                Text(failure)
            }
    }

    private var isShowingFailure: Binding<Bool> {
        Binding {
            merger.failure != nil
        } set: { isShowing in
            if !isShowing {
                merger.failure = nil
            }
        }
    }
}
