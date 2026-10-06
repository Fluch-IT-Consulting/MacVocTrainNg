import SwiftUI
import VocabCore

/// Details of the selected card: editable content, learning state and review log.
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
                    Button("Reset Learning State") {
                        document.resetLearningState(of: selection, undoManager: undoManager)
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
        case question, answer, hint
    }

    @ObservedObject var document: VocabularyDocument
    let card: Card
    @Environment(\.undoManager) private var undoManager
    @State private var question: String
    @State private var answer: String
    @State private var hint: String
    @FocusState private var focus: Field?

    init(document: VocabularyDocument, card: Card) {
        self.document = document
        self.card = card
        _question = State(initialValue: card.question)
        _answer = State(initialValue: card.answer)
        _hint = State(initialValue: card.hint)
    }

    var body: some View {
        Form {
            Section("Card") {
                TextField("Question", text: $question, axis: .vertical)
                    .focused($focus, equals: .question)
                TextField("Answer", text: $answer, axis: .vertical)
                    .focused($focus, equals: .answer)
                TextField("Hint", text: $hint, axis: .vertical)
                    .focused($focus, equals: .hint)
            }
            .onSubmit(commit)

            Section("Learning State") {
                if let learningState = card.learningState {
                    LabeledContent("Maturity") { MaturityLabel(category: MaturityCategory(card: card)) }
                    LabeledContent("Phase", value: learningState.phase.title)
                    // Due date and recall probability change as time passes, so these rows
                    // are re-evaluated every minute. The text fields above stay outside the
                    // tick.
                    TimelineView(.everyMinute) { _ in
                        LabeledContent("Due", value: Format.due(card, now: document.clock.now))
                    }
                    LabeledContent("Stability", value: Format.days(learningState.stability))
                    LabeledContent("Difficulty", value: learningState.difficulty.formatted(.number.precision(.fractionLength(1))) + " / 10")
                    TimelineView(.everyMinute) { _ in
                        LabeledContent("Recall Probability", value: Format.percent(recallProbability(learningState)))
                    }
                    LabeledContent("Reviews", value: learningState.reviews.formatted())
                    LabeledContent("Lapses", value: learningState.lapses.formatted())
                    LabeledContent("Last Review", value: learningState.lastReview.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("This card has not been studied yet.")
                        .foregroundStyle(.secondary)
                }
                if !card.isNew {
                    Button("Reset Learning State") {
                        document.resetLearningState(of: [card.id], undoManager: undoManager)
                    }
                }
            }

            if !card.log.isEmpty {
                Section("Review Log") {
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
            hint = card.hint
        }
        .onDisappear(perform: commit)
    }

    private func recallProbability(_ learningState: LearningState) -> Double {
        Scheduler(learningOptions: document.deck.learningOptions, calendar: document.calendar)
            .recallProbability(of: learningState, at: document.clock.now)
    }

    /// Writes edited text back to the document as one undoable change.
    private func commit() {
        guard question != card.question || answer != card.answer || hint != card.hint,
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
        current.hint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        document.update(current, undoManager: undoManager)
    }
}
