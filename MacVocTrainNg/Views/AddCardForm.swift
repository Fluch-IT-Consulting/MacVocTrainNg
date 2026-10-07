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
    /// Counts Return presses; `onChange` submits. SwiftUI on macOS renews a field's
    /// submit action only when the field's text changes, so Return in a hint field that
    /// stayed empty runs the action of the first render, where `undoManager` was still
    /// `nil`: the card was added without undo, and the document wasn't marked as changed.
    /// Setting state works from any copy of the view; `onChange` runs the current one.
    @State private var submitRequests = 0

    /// `nil` until question and answer are filled in.
    private var text: CardText? { CardText(question: question, answer: answer, hint: hint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Question", text: $question)
                    .focused($focus, equals: .question)
                TextField("Answer", text: $answer, prompt: Text("Answer (alternatives separated by /)"))
                    .focused($focus, equals: .answer)
                TextField("Hint", text: $hint, prompt: Text("Hint (optional)"))
                    .focused($focus, equals: .hint)
                    .frame(maxWidth: 200)
                Button("Add") { submit(fromButton: true) }
                    .disabled(text == nil)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { submitRequests += 1 }
            .onChange(of: submitRequests) { submit() }

            if let duplicate = document.deck.cards(withQuestion: question).first {
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
        guard let text else {
            focus = CardText.trimmed(question).isEmpty ? .question : .answer
            return
        }
        onAdd(document.add(text, undoManager: undoManager))
        question = ""
        answer = ""
        hint = ""
        focus = .question
    }
}
