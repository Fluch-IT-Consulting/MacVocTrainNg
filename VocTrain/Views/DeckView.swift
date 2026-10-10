import SwiftUI

/// The screen of an open deck: how many cards it holds and how many are due.
struct DeckView: View {
    @ObservedObject var document: VocabularyDocument
    /// The document's undo manager, which SwiftUI hands only to views. The document
    /// gets it from here, as from `DocumentView` on the Mac.
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        List {
            LabeledContent("Cards", value: document.deck.cards.count, format: .number)
            LabeledContent("Due Now", value: document.dueCards.count, format: .number)
        }
        .onChange(of: undoManager, initial: true) {
            document.undoManager = undoManager
        }
    }
}
