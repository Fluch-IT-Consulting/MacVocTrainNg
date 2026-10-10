import SwiftUI

/// The content of a document scene, for as long as the deck is open.
///
/// As on the Mac, SwiftUI hands the scene a new document when UIDocument reads the file
/// again after another device changed it. The deck view then starts afresh: a session
/// would go on changing the old document, which nobody saves. The `VersionMerger`
/// stays, so it can keep what the old document held that the file lacks. See
/// `DocumentWindow` in the Mac app. The deck view shows what the merger reports: an
/// alert from here would come while the session leaves the screen, and get lost.
struct DocumentScreen: View {
    var file: ReferenceFileDocumentConfiguration<VocabularyDocument>
    @State private var merger = VersionMerger()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DeckView(document: file.document, fileURL: file.fileURL, isEditable: file.isEditable, merger: merger)
            .id(ObjectIdentifier(file.document))
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: merger.suspend()
                case .active: merger.resume()
                default: break
                }
            }
    }
}
