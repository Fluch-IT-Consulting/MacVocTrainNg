import SwiftUI
import VocabCore

/// The screen of an open deck: how many cards are due, when the next one is, and the
/// start of a study session.
///
/// Shows one document for its whole life: each document gets a view of its own, see
/// `DeckScreen`.
struct DeckView: View {
    @ObservedObject var document: VocabularyDocument
    /// Where the document is saved.
    var fileURL: URL?
    /// `false` while the deck can only be viewed, e.g. a file that can't be written;
    /// studying is then disabled.
    var isEditable: Bool
    /// Merges the versions of the deck from the Mac; outlives the view.
    var merger: VersionMerger
    /// The undo manager of the deck's file, which counts the changes to save.
    var undoManager: UndoManager
    @State private var study: StudyModel?

    var body: some View {
        let dueCount = document.dueCards.count

        List {
            if merger.endedSession {
                Notice(title: "The study session has ended", message: Text("The deck was changed on another device and opened anew. The reviews of the session are kept.")) {
                    merger.endedSession = false
                }
            }
            if let failure = merger.failure {
                Notice(title: "Another version of this deck could not be merged", message: Text(failure)) {
                    merger.failure = nil
                }
            }

            if document.deck.cards.isEmpty {
                EmptyDeckNotice()
            }

            Section {
                LabeledContent("Cards", value: document.deck.cards.count, format: .number)
                LabeledContent("Due Now", value: dueCount, format: .number)
                if document.deck.suspendedCount > 0 {
                    LabeledContent("Suspended", value: document.deck.suspendedCount, format: .number)
                }
                if dueCount == 0, let nextDue {
                    LabeledContent("Next Due", value: Format.due(nextDue, now: document.clock.now))
                }
            }

            Section {
                Button {
                    merger.endedSession = false
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
        .documentSync(document, fileURL: fileURL, isEditable: isEditable, merger: merger, isInSession: study != nil, undoManager: undoManager)
        .fullScreenCover(item: $study) { model in
            StudyView(model: model) { study = nil }
        }
    }

    /// When the next card becomes due; new cards are due at once, suspended ones never.
    private var nextDue: Date? {
        document.deck.cards.lazy.filter { !$0.isSuspended }.compactMap(\.learningState?.due).min()
    }
}

/// Explains a deck without cards (#266): this app never adds cards.
private struct EmptyDeckNotice: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("This deck has no cards", systemImage: "rectangle.stack")
                    .font(.headline)
                Text("Decks are created and edited in MacVocTrain on the Mac. Here you only study them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// What the `VersionMerger` reports, at the top of the deck until dismissed.
private struct Notice: View {
    var title: LocalizedStringKey
    var message: Text
    var dismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "exclamationmark.triangle")
                    .font(.headline)
                message
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Dismiss", action: dismiss)
        }
    }
}
