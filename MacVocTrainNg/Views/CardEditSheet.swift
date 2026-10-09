import SwiftUI
import VocabCore

/// Edits question, answer and hint of one card in a sheet.
///
/// The fields hold a draft; the deck changes only when the learner saves it, as one
/// change with one undo action (#241). Cancel drops the draft, and so does quitting
/// while the sheet is open, as with the learning options: the deck holds what the
/// learner confirmed. Typing registers with the undo manager of the sheet's own window
/// (#48), so ⌘Z in the sheet takes back typing, never a change to the deck.
struct CardEditSheet: View {
    @ObservedObject var document: VocabularyDocument
    let cardID: Card.ID
    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var answer: String
    @State private var hint: String

    init(document: VocabularyDocument, card: Card) {
        self.document = document
        cardID = card.id
        _question = State(initialValue: card.question)
        _answer = State(initialValue: card.answer)
        _hint = State(initialValue: card.hint)
    }

    /// `nil` while question or answer is empty; Save is disabled then.
    private var text: CardText? { CardText(question: question, answer: answer, hint: hint) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Question", text: $question)
                    TextField("Answer", text: $answer, prompt: Text("Answer (alternatives separated by /)"))
                    TextField("Hint", text: $hint, prompt: Text("Hint (optional)"))
                } footer: {
                    // As in the form for new cards, but the edited card doesn't count.
                    if let duplicate = document.deck.cards(withQuestion: question).first(where: { $0.id != cardID }) {
                        Label("Already in this deck: \(duplicate.question) → \(duplicate.answer)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            // A form scrolls: at its own height the sheet grows with the note about a
            // duplicate instead of cutting it off.
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text == nil)
            }
            .padding()
        }
        .frame(width: 460)
        .navigationTitle("Edit Card")
    }

    /// Changes the card once, with the whole draft. A card that left the deck while the
    /// sheet was open stays out: `editText(of:to:)` changes nothing then.
    private func save() {
        guard let text else { return }
        document.editText(of: cardID, to: text)
        dismiss()
    }
}
