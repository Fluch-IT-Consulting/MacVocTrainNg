import SwiftUI

/// The iPhone app: studies a deck that the Mac app keeps, opened from the Files app or
/// iCloud Drive (#254). It never edits cards; that is left to the Mac app.
///
/// The deck is the same `VocabularyDocument` as on the Mac, from the folder `Shared`.
/// At launch the app opens the deck it showed last, see `LastDeck`.
@main
struct VocTrainApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Only the first activation is a launch; later ones come back from the background.
    @State private var hasReopened = false

    var body: some Scene {
        DocumentGroup(
            newDocument: { VocabularyDocument() },
            editor: { file in
                DocumentScreen(file: file)
            }
        )
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, !hasReopened else { return }
            hasReopened = true
            // The app hosting the tests leaves the simulator's deck closed: the tests
            // open their own.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            Task { await LastDeck().reopen() }
        }
    }
}
