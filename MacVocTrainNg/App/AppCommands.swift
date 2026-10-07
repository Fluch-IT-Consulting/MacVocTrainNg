import SwiftUI

/// Actions of the focused document window, for the menu bar.
struct DeckActions {
    var isInSession: Bool
    var canStartSession: Bool
    var startSession: () -> Void
    var show: (DocumentView.Screen) -> Void
    var showOptions: () -> Void
    var importCards: () -> Void
    var exportCards: () -> Void
}

private struct DeckActionsKey: FocusedValueKey {
    typealias Value = DeckActions
}

extension FocusedValues {
    var deckActions: DeckActions? {
        get { self[DeckActionsKey.self] }
        set { self[DeckActionsKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.deckActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import MacVocTrain 1 Document…") {
                LegacyImport.run()
            }
            Button("Import Cards…") { actions?.importCards() }
                .disabled(actions == nil || actions?.isInSession == true)
            Button("Export Cards…") { actions?.exportCards() }
                .disabled(actions == nil)
        }

        CommandMenu("Study") {
            Button("Start Session") { actions?.startSession() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions?.canStartSession != true)

            Divider()

            Button("Cards") { actions?.show(.cards) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(actions == nil || actions?.isInSession == true)
            Button("Statistics") { actions?.show(.statistics) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(actions == nil || actions?.isInSession == true)

            Divider()

            Button("Learning Options…") { actions?.showOptions() }
                .disabled(actions == nil || actions?.isInSession == true)
        }
    }
}
