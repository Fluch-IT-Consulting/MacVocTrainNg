import SwiftUI
import VocabCore

/// The screen of an open deck: how many cards are due, when the next one is, and the
/// start of a study session.
struct DeckView: View {
    @ObservedObject var document: VocabularyDocument
    /// The document's undo manager, which SwiftUI hands only to views. The document
    /// gets it from here, as from `DocumentView` on the Mac.
    @Environment(\.undoManager) private var undoManager
    @State private var study: StudyModel?

    var body: some View {
        let dueCount = document.dueCards.count

        List {
            Section {
                LabeledContent("Cards", value: document.deck.cards.count, format: .number)
                LabeledContent("Due Now", value: dueCount, format: .number)
                if dueCount == 0, let nextDue {
                    LabeledContent("Next Due", value: Format.due(nextDue, now: document.clock.now))
                }
            }

            Section {
                Button {
                    study = StudyModel(document: document)
                } label: {
                    Label(dueCount > 0 ? "Study (\(dueCount))" : "Study", systemImage: "graduationcap")
                }
                .disabled(dueCount == 0)
            } footer: {
                if dueCount == 0 {
                    Text("No cards are due")
                }
            }
        }
        .onChange(of: undoManager, initial: true) {
            document.undoManager = undoManager
        }
        .fullScreenCover(item: $study) { model in
            StudyView(model: model) { study = nil }
        }
    }

    /// When the next card becomes due; new cards are due at once.
    private var nextDue: Date? {
        document.deck.cards.compactMap(\.learningState?.due).min()
    }
}
