import SwiftUI

/// The iPhone app: studies a deck that the Mac app keeps, opened from the Files app or
/// iCloud Drive (#254). It never edits cards; that is left to the Mac app.
///
/// The deck is the same `VocabularyDocument` as on the Mac, from the folder `Shared`.
@main
struct VocTrainApp: App {
    var body: some Scene {
        DocumentGroup(
            newDocument: { VocabularyDocument() },
            editor: { file in
                DocumentScreen(file: file)
            }
        )
    }
}
