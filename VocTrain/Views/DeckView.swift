import SwiftUI
import VocabCore

/// The screen of an open deck: how many cards are due, when the next one is, and the
/// start of a study session.
///
/// Shows one document for its whole life: the scene gives each document a view of its
/// own, see `DocumentScreen`.
struct DeckView: View {
    @ObservedObject var document: VocabularyDocument
    /// Where the document is saved.
    var fileURL: URL?
    /// `false` while the deck can only be viewed, e.g. a file that can't be written;
    /// studying is then disabled.
    var isEditable: Bool
    /// Merges the versions of the deck from the Mac; outlives the view.
    var merger: VersionMerger
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
                .disabled(dueCount == 0 || !isEditable)
            } footer: {
                if dueCount == 0 {
                    Text("No cards are due")
                }
            }
        }
        .onChange(of: undoManager, initial: true) {
            document.undoManager = undoManager
            attachToMerger()
        }
        .onChange(of: fileURL, attachToMerger)
        .onChange(of: isEditable, attachToMerger)
        .onChange(of: study == nil) { _, hasNoSession in
            merger.isInSession = !hasNoSession
        }
        .fullScreenCover(item: $study) { model in
            StudyView(model: model) { study = nil }
        }
    }

    private func attachToMerger() {
        merger.attach(document, fileURL: fileURL, isEditable: isEditable)
    }

    /// When the next card becomes due; new cards are due at once.
    private var nextDue: Date? {
        document.deck.cards.compactMap(\.learningState?.due).min()
    }
}
