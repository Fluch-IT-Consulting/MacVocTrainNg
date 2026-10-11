import SwiftUI
import VocabCore

/// A study session in the style of flash cards: the question, a tap shows the answer,
/// and the learner grades with Again and Good, or with Hard and Easy below them.
struct StudyView: View {
    var model: StudyModel
    var onClose: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if model.isFinished {
                    StudySummaryView(model: model, onClose: onClose)
                } else if let card = model.currentCard {
                    cardArea(card)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !model.isFinished {
                        Button("End Session", action: onClose)
                    }
                }
                ToolbarItem(placement: .principal) {
                    if !model.isFinished {
                        progress
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Only reviews of this session: undo beyond them would change cards
                    // the session doesn't show.
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        model.document.undoManager?.undo()
                    }
                    .disabled(model.session.reviewCount == 0 || model.document.undoManager?.canUndo != true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var progress: some View {
        let session = model.session
        return VStack(spacing: 4) {
            Text("\(session.completedCount) / \(session.totalCount)")
                .font(.subheadline)
                .monospacedDigit()
            ProgressView(value: Double(session.completedCount), total: Double(max(session.totalCount, 1)))
                .frame(width: 120)
        }
    }

    /// In portrait the buttons sit below the card. In landscape the iPhone is too low
    /// for that, so they take a column to the right of the card, both centred in height.
    @ViewBuilder
    private func cardArea(_ card: Card) -> some View {
        if verticalSizeClass == .compact {
            HStack(spacing: 24) {
                cardText(card, centered: true)
                actions
                    .frame(width: 260)
            }
            .padding()
        } else {
            VStack(spacing: 24) {
                cardText(card, centered: false)
                actions
            }
            .padding()
        }
    }

    /// Centred, the card keeps room for the hidden answer, so the question doesn't
    /// move up when the answer shows.
    private func cardText(_ card: Card, centered: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Text(card.question)
                        .font(.largeTitle.weight(.semibold))
                    if !card.hint.isEmpty {
                        Text(card.hint)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if model.stage == .revealed || centered {
                        let revealed = model.stage == .revealed
                        Group {
                            Divider()
                            Text(card.answer)
                                .font(.largeTitle)
                        }
                        .opacity(revealed ? 1 : 0)
                        .accessibilityHidden(!revealed)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: centered ? geometry.size.height : nil)
                .padding(.top, centered ? 0 : 48)
            }
        }
        // The whole card shows the answer, not only the button.
        .contentShape(Rectangle())
        .onTapGesture { model.reveal() }
    }

    @ViewBuilder
    private var actions: some View {
        if model.stage == .revealed {
            GradeButtons(onGrade: model.grade)
        } else {
            Button {
                model.reveal()
            } label: {
                Text("Show Answer")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// Again and Good large, as they are the usual grades; Hard and Easy small. Good stays
/// the grade for a word one knew, so cards don't jump to long intervals.
private struct GradeButtons: View {
    var onGrade: @MainActor (Grade) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                button(.hard, prominent: false)
                button(.easy, prominent: false)
            }
            HStack(spacing: 12) {
                button(.again, prominent: true)
                button(.good, prominent: true)
            }
        }
    }

    @ViewBuilder
    private func button(_ grade: Grade, prominent: Bool) -> some View {
        let button = Button {
            onGrade(grade)
        } label: {
            Text(grade.title)
                .frame(maxWidth: .infinity, minHeight: prominent ? 56 : 32)
        }
        .tint(grade.color)
        if prominent {
            button
                .buttonStyle(.borderedProminent)
                .font(.title3.weight(.semibold))
        } else {
            button
                .buttonStyle(.bordered)
        }
    }
}
