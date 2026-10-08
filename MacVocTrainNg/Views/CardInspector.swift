import SwiftUI
import VocabCore

/// Details of the selected card: editable content, learning state and review log.
struct CardInspector: View {
    @ObservedObject var document: VocabularyDocument
    var selection: Set<Card.ID>
    /// Deletes cards and takes them out of the selection, which belongs to the card list.
    var onDelete: (Set<Card.ID>) -> Void

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
                        document.resetLearningState(of: selection)
                    }
                    Button("Delete", role: .destructive) {
                        onDelete(selection)
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
            .onSubmit(endEdit)

            Section("Learning State") {
                if let learningState = card.learningState {
                    LabeledContent("Maturity") { MaturityLabel(category: MaturityCategory(card: card)) }
                    LabeledContent("Phase", value: learningState.phase.title)
                    // Due date and recall probability change as time passes, so these rows
                    // are re-evaluated every minute. The text fields above stay outside the
                    // tick.
                    TimelineView(.everyMinute) { _ in
                        LabeledContent("Due", value: Format.due(learningState.due, now: document.clock.now))
                    }
                    LabeledContent("Stability", value: Format.days(learningState.stability))
                    LabeledContent("Difficulty", value: learningState.difficulty.formatted(.number.precision(.fractionLength(1))) + " / 10")
                    TimelineView(.everyMinute) { _ in
                        if let probability = document.deck.recallProbability(of: card, at: document.clock.now, calendar: document.calendar) {
                            LabeledContent("Recall Probability", value: Format.percent(probability))
                        }
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
                        document.resetLearningState(of: [card.id])
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
        .onChange(of: [question, answer, hint]) {
            write()
        }
        .onChange(of: focus) { oldValue, _ in
            if oldValue != nil { endEdit() }
        }
        .onChange(of: [card.question, card.answer, card.hint]) {
            // Show changes made elsewhere, e.g. by undo. Changes of the learning state
            // leave the fields alone, so they keep what is being typed (#175).
            showText(of: card, unlessTyped: true)
        }
        .onDisappear {
            document.endTextEdit(of: card.id)
        }
    }

    /// Writes the text in the fields to the deck as it is typed, so it is there when
    /// the deck is saved, closed or the app quits (#175). The document makes one
    /// undo action of an edit, see `VocabularyDocument.editText(of:to:)`. A text the
    /// deck doesn't take, like an empty question, stays in the fields only.
    private func write() {
        guard let text = CardText(question: question, answer: answer, hint: hint) else { return }
        document.editText(of: card.id, to: text)
    }

    /// Ends the edit when a field loses the focus or Return is pressed: the next one
    /// is an undo action of its own. The fields show the text as the deck took it,
    /// trimmed, or the last one it took if they hold one it doesn't.
    private func endEdit() {
        document.endTextEdit(of: card.id)
        if let current = document.card(withID: card.id) {
            showText(of: current, unlessTyped: false)
        }
    }

    /// Shows the text of `card` in the fields. With `unlessTyped`, fields that the deck
    /// would take as the text of `card` stay as typed, with a trailing space for example.
    private func showText(of card: Card, unlessTyped: Bool) {
        if unlessTyped, CardText(question: question, answer: answer, hint: hint) == CardText(question: card.question, answer: card.answer, hint: card.hint) {
            return
        }
        question = card.question
        answer = card.answer
        hint = card.hint
    }
}
