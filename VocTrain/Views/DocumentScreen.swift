import SwiftUI

/// The content of a document scene, for as long as the deck is open.
///
/// As on the Mac, SwiftUI hands the scene a new document when UIDocument reads the file
/// again after another device changed it. The deck view then starts afresh: a session
/// would go on changing the old document, which nobody saves. The `VersionMerger`
/// stays, so it can keep what the old document held that the file lacks. See
/// `DocumentWindow` in the Mac app.
struct DocumentScreen: View {
    var file: ReferenceFileDocumentConfiguration<VocabularyDocument>
    @State private var merger = VersionMerger()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DeckView(document: file.document, fileURL: file.fileURL, isEditable: file.isEditable, merger: merger)
            .id(ObjectIdentifier(file.document))
            .alert("The study session has ended", isPresented: $merger.endedSession) {
            } message: {
                Text("The deck was changed on another device and opened anew. The reviews of the session are kept.")
            }
            .alert("Another version of this deck could not be merged", isPresented: isShowingFailure, presenting: merger.failure) { _ in
            } message: { failure in
                Text(failure)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: merger.suspend()
                case .active: merger.resume()
                default: break
                }
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
