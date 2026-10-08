import SwiftUI

@main
struct MacVocTrainApp: App {
    init() {
        Preferences.setUpDefaults(.standard, domain: Bundle.main.bundleIdentifier ?? "")
    }

    var body: some Scene {
        DocumentGroup(newDocument: { VocabularyDocument() }) { file in
            // SwiftUI hands the window a new document when NSDocument reads the file again,
            // e.g. on reverting to a saved version. The window then starts afresh: a
            // session or sheet would go on changing the old document, which nobody saves.
            DocumentView(document: file.document, fileURL: file.fileURL, isEditable: file.isEditable)
                .id(ObjectIdentifier(file.document))
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

    /// Reopen the decks that were open at quit. The key is AppKit's own, which also
    /// handles ⌥⌘Q; in the app's domain it overrides the system setting "Close windows
    /// when quitting an application".
    static let reopenDecksKey = "NSQuitAlwaysKeepsWindows"

    /// Writes the defaults that a registered default can't provide into `domain`, the
    /// persistent domain of `defaults`: the global domain would win over a registered
    /// `reopenDecksKey`.
    static func setUpDefaults(_ defaults: UserDefaults, domain: String) {
        if defaults.persistentDomain(forName: domain)?[reopenDecksKey] == nil {
            defaults.set(true, forKey: reopenDecksKey)
        }
    }
}
