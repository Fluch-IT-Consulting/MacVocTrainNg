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
                    // In landscape the progress sits between the grade buttons.
                    if !model.isFinished && verticalSizeClass != .compact {
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
    /// for that: the card takes the full width, the buttons one row below it, half to
    /// each side of the progress.
    @ViewBuilder
    private func cardArea(_ card: Card) -> some View {
        if verticalSizeClass == .compact {
            VStack(spacing: 12) {
                cardText(card, centered: true)
                buttonRow
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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    GradeButton(grade: .hard, onGrade: model.grade)
                    GradeButton(grade: .easy, onGrade: model.grade)
                }
                HStack(spacing: 12) {
                    GradeButton(grade: .again, isTall: true, onGrade: model.grade)
                    GradeButton(grade: .good, isTall: true, onGrade: model.grade)
                }
            }
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

    /// Again, Hard, the progress, Easy, Good. Before the answer shows, the right half
    /// holds the button that shows it; the left half stays empty, so the progress stays
    /// in the middle.
    private var buttonRow: some View {
        HStack(spacing: 12) {
            if model.stage == .revealed {
                GradeButton(grade: .again, onGrade: model.grade)
                GradeButton(grade: .hard, onGrade: model.grade)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: 0)
            }
            progress
            if model.stage == .revealed {
                GradeButton(grade: .easy, onGrade: model.grade)
                GradeButton(grade: .good, onGrade: model.grade)
            } else {
                Button {
                    model.reveal()
                } label: {
                    Text("Show Answer")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Again and Good stand out, as they are the usual grades; in portrait they are also
/// taller than Hard and Easy. Good stays the grade for a word one knew, so cards don't
/// jump to long intervals.
private struct GradeButton: View {
    var grade: Grade
    var isTall = false
    var onGrade: @MainActor (Grade) -> Void

    var body: some View {
        let button = Button {
            onGrade(grade)
        } label: {
            Text(grade.title)
                .frame(maxWidth: .infinity, minHeight: isTall ? 56 : 32)
        }
        .tint(grade.color)
        if grade == .again || grade == .good {
            button
                .buttonStyle(.borderedProminent)
                .font(isTall ? .title3.weight(.semibold) : .body.weight(.semibold))
        } else {
            button
                .buttonStyle(.bordered)
        }
    }
}
