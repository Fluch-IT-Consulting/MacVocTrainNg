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
                        Button("End Session", systemImage: "chevron.backward", action: onClose)
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
            // iOS 26 adds a back button of its own; End Session takes its place.
            .navigationBarBackButtonHidden()
        }
    }

    /// The progress in the row of buttons: the bar at the height of their middle, the
    /// numbers small below it.
    private var rowProgress: some View {
        let session = model.session
        return ProgressView(value: Double(session.completedCount), total: Double(max(session.totalCount, 1)))
            .frame(width: 120)
            .overlay(alignment: .top) {
                Text("\(session.completedCount) / \(session.totalCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 8)
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
    /// move up when the answer shows. It scrolls only if it doesn't fit, so that it is
    /// centred in the space it has, like the buttons below it.
    private func cardText(_ card: Card, centered: Bool) -> some View {
        Group {
            if centered {
                ViewThatFits(in: .vertical) {
                    cardContent(card, reservesAnswer: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ScrollView {
                        cardContent(card, reservesAnswer: true)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ScrollView {
                    cardContent(card, reservesAnswer: false)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
        }
        // The whole card shows the answer, not only the button.
        .contentShape(Rectangle())
        .onTapGesture { model.reveal() }
    }

    private func cardContent(_ card: Card, reservesAnswer: Bool) -> some View {
        VStack(spacing: 16) {
            Text(card.question)
                .font(.largeTitle.weight(.semibold))
            if !card.hint.isEmpty {
                Text(card.hint)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if model.stage == .revealed || reservesAnswer {
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

    /// Again, Hard, the progress, Easy, Good. Before the answer shows, a short Show
    /// button takes the place of Good; the other places stay empty, so the progress
    /// stays in the middle.
    private var buttonRow: some View {
        HStack(spacing: 12) {
            if model.stage == .revealed {
                GradeButton(grade: .again, onGrade: model.grade)
                GradeButton(grade: .hard, onGrade: model.grade)
                rowProgress
                GradeButton(grade: .easy, onGrade: model.grade)
                GradeButton(grade: .good, onGrade: model.grade)
            } else {
                emptyPlace
                emptyPlace
                rowProgress
                emptyPlace
                Button {
                    model.reveal()
                } label: {
                    Text("Show")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyPlace: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 0)
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
