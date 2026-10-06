import SwiftUI
import VocabCore

/// The row of fields for entering new cards.
///
/// Return moves to the next empty required field, or adds the card once question
/// and answer are filled in; the hint is optional. After adding, the fields are
/// cleared and the cursor returns to the question, ready for the next card.
struct AddCardForm: View {
    private enum Field: Hashable {
        case question, answer, hint
    }

    @ObservedObject var document: VocabularyDocument
    var onAdd: (Card.ID) -> Void

    @Environment(\.undoManager) private var undoManager
    @State private var question = ""
    @State private var answer = ""
    @State private var hint = ""
    @FocusState private var focus: Field?

    private var trimmedQuestion: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmedQuestion.isEmpty && !trimmedAnswer.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Question", text: $question)
                    .focused($focus, equals: .question)
                    .onSubmit { submit() }
                TextField("Answer", text: $answer, prompt: Text("Answer (alternatives separated by /)"))
                    .focused($focus, equals: .answer)
                    .onSubmit { submit() }
                TextField("Hint", text: $hint, prompt: Text("Hint (optional)"))
                    .focused($focus, equals: .hint)
                    .onSubmit { submit() }
                    .frame(maxWidth: 200)
                Button("Add") { submit(fromButton: true) }
                    .disabled(!canAdd)
            }
            .textFieldStyle(.roundedBorder)

            if let duplicate = document.cards(withQuestion: question).first {
                Label("Already in this deck: \(duplicate.question) → \(duplicate.answer)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if document.deck.cards.isEmpty {
                focus = .question
            }
        }
    }

    private func submit(fromButton: Bool = false) {
        guard canAdd else {
            if trimmedQuestion.isEmpty {
                focus = .question
            } else if trimmedAnswer.isEmpty {
                focus = .answer
            }
            return
        }
        let card = Card(
            question: trimmedQuestion,
            answer: trimmedAnswer,
            hint: hint.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        document.add(card, undoManager: undoManager)
        onAdd(card.id)
        question = ""
        answer = ""
        hint = ""
        focus = .question
    }
}
