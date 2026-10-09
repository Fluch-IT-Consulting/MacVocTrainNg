import SwiftUI
import VocabCore

/// Details of the selected card: its texts, learning state and review log.
///
/// The texts are only shown. "Edit…" opens the sheet that edits them, so the deck
/// changes only once the learner saves the edit (#241).
struct CardInspector: View {
    @ObservedObject var document: VocabularyDocument
    var selection: Set<Card.ID>
    /// `false` while the deck can only be viewed: the inspector then only shows the cards.
    var isEditable: Bool
    /// Opens the sheet that edits a card, which the card list presents.
    var onEdit: (Card.ID) -> Void
    /// Deletes cards and takes them out of the selection, which belongs to the card list.
    var onDelete: (Set<Card.ID>) -> Void

    var body: some View {
        Group {
            if selection.count == 1, let id = selection.first, let card = document.card(withID: id) {
                CardDetail(document: document, card: card, isEditable: isEditable, onEdit: onEdit)
                    .id(card.id)
            } else if selection.count > 1 {
                VStack(spacing: 12) {
                    Text("\(selection.count) cards selected")
                        .font(.headline)
                    Group {
                        Button("Reset Learning State") {
                            document.resetLearningState(of: selection)
                        }
                        Button("Delete", role: .destructive) {
                            onDelete(selection)
                        }
                    }
                    .disabled(!isEditable)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Selection", systemImage: "rectangle.on.rectangle.slash", description: Text("Select a card to see its details."))
            }
        }
    }
}

private struct CardDetail: View {
    @ObservedObject var document: VocabularyDocument
    let card: Card
    let isEditable: Bool
    let onEdit: (Card.ID) -> Void

    var body: some View {
        Form {
            Section("Card") {
                LabeledContent("Question") { Text(card.question).textSelection(.enabled) }
                LabeledContent("Answer") { Text(card.answer).textSelection(.enabled) }
                if !card.hint.isEmpty {
                    LabeledContent("Hint") { Text(card.hint).textSelection(.enabled) }
                }
                Button("Edit…") { onEdit(card.id) }
                    .disabled(!isEditable)
            }

            Section("Learning State") {
                if let learningState = card.learningState {
                    LabeledContent("Maturity") { MaturityLabel(category: MaturityCategory(card: card)) }
                    LabeledContent("Phase", value: learningState.phase.title)
                    // Due date and recall probability change as time passes, so these rows
                    // are re-evaluated every minute.
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
                    .disabled(!isEditable)
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
    }
}
