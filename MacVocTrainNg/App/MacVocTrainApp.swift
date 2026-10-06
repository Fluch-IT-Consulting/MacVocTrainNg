import SwiftUI

@main
struct MacVocTrainApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { VocabularyDocument() }) { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            AppCommands()
        }

        Settings {
            PreferencesView()
        }
    }
}

/// App-wide preferences, stored in the user defaults.
enum Preferences {
    /// Move on to the next card right after a correct response instead of asking for a grade.
    static let autoAdvanceKey = "autoAdvanceOnCorrectAnswer"

    static var autoAdvance: Bool {
        UserDefaults.standard.object(forKey: autoAdvanceKey) as? Bool ?? true
    }
}
