import SwiftUI
import VocabCore

/// Details of the selected card: editable content, learning state and history.
struct CardInspector: View {
    @ObservedObject var document: VocabularyDocument
    var selection: Set<Card.ID>
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if selection.count == 1, let id = selection.first, let card = document.card(withID: id) {
                CardDetail(document: document, card: card)
                    .id(card.id)
            } else if selection.count > 1 {
                VStack(spacing: 12) {
                    Text("\(selection.count) cards selected")
                        .font(.headline)
                    Button("Reset Progress") {
                        document.resetProgress(of: selection, undoManager: undoManager)
                    }
                    Button("Delete", role: .destructive) {
                        document.delete(selection, undoManager: undoManager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Selection", systemImage: "rectangle.on.rectangle.slash", description: Text("Select a card to see its details."))
            }
        }
    }
}

private struct CardDetail: View {
    private enum Field: Hashable {
        case question, answer, remark
    }

    @ObservedObject var document: VocabularyDocument
    let card: Card
    @Environment(\.undoManager) private var undoManager
    @State private var question: String
    @State private var answer: String
    @State private var remark: String
    @FocusState private var focus: Field?

    init(document: VocabularyDocument, card: Card) {
        self.document = document
        self.card = card
        _question = State(initialValue: card.question)
        _answer = State(initialValue: card.answer)
        _remark = State(initialValue: card.remark)
    }

    var body: some View {
        Form {
            Section("Card") {
                TextField("Question", text: $question, axis: .vertical)
                    .focused($focus, equals: .question)
                TextField("Answer", text: $answer, axis: .vertical)
                    .focused($focus, equals: .answer)
                TextField("Hint", text: $remark, axis: .vertical)
                    .focused($focus, equals: .remark)
            }
            .onSubmit(commit)

            Section("Learning State") {
                if let memory = card.memory {
                    LabeledContent("Status") { MaturityLabel(category: MaturityCategory(card: card)) }
                    LabeledContent("Phase", value: memory.phase.title)
                    LabeledContent("Due", value: Format.due(card))
                    LabeledContent("Stability", value: Format.days(memory.stability))
                    LabeledContent("Difficulty", value: memory.difficulty.formatted(.number.precision(.fractionLength(1))) + " / 10")
                    LabeledContent("Recall Probability", value: Format.percent(recallProbability(memory)))
                    LabeledContent("Reviews", value: memory.reps.formatted())
                    LabeledContent("Lapses", value: memory.lapses.formatted())
                    LabeledContent("Last Review", value: memory.lastReview.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("This card has not been studied yet.")
                        .foregroundStyle(.secondary)
                }
                if !card.isNew {
                    Button("Reset Progress") {
                        document.resetProgress(of: [card.id], undoManager: undoManager)
                    }
                }
            }

            if !card.log.isEmpty {
                Section("History") {
                    ForEach(Array(card.log.suffix(50).reversed().enumerated()), id: \.offset) { _, entry in
                        LabeledContent(entry.date.formatted(date: .abbreviated, time: .shortened)) {
                            Text(entry.grade.title)
                                .foregroundStyle(entry.grade.color)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: focus) { oldValue, _ in
            if oldValue != nil { commit() }
        }
        .onChange(of: card) { _, card in
            // Show changes made elsewhere, e.g. by undo.
            question = card.question
            answer = card.answer
            remark = card.remark
        }
        .onDisappear(perform: commit)
    }

    private func recallProbability(_ memory: MemoryState) -> Double {
        let fsrs = FSRS(parameters: document.deck.settings.parameters)
        let elapsed = Date().timeIntervalSince(memory.lastReview) / 86400
        return fsrs.retrievability(elapsedDays: elapsed, stability: memory.stability)
    }

    /// Writes edited text back to the document as one undoable change.
    private func commit() {
        guard question != card.question || answer != card.answer || remark != card.remark,
              var current = document.card(withID: card.id)
        else { return }
        let newQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newQuestion.isEmpty, !newAnswer.isEmpty else {
            question = current.question
            answer = current.answer
            return
        }
        current.question = newQuestion
        current.answer = newAnswer
        current.remark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        document.update(current, undoManager: undoManager)
    }
}
