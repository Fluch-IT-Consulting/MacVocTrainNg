import SwiftUI
import VocabCore

/// The study screen: asks one card after another.
///
/// Keyboard flow: type the answer and press Return. A correct answer moves on
/// directly (unless disabled in Settings). Otherwise the correct answer is shown
/// and Return accepts the suggested grade; 1–4 choose a grade explicitly, e.g. 3
/// when the answer was right after all. ⌘Z takes back the last answer.
struct StudyView: View {
    @Bindable var model: StudyViewModel
    var onClose: () -> Void
    @ObservedObject private var document: VocabularyDocument

    init(model: StudyViewModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        document = model.document
    }

    @Environment(\.undoManager) private var undoManager
    @FocusState private var answerFocused: Bool
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isFinished {
                SessionSummaryView(model: model, onClose: onClose)
            } else if let card = model.currentCard {
                cardArea(card)
            }
            if let previous = model.previous, !model.isFinished {
                Divider()
                PreviousAnswerBar(previous: previous)
            }
        }
        .onChange(of: document.deck.cards.count) {
            model.documentDidChange()
        }
        .confirmationDialog("End this session?", isPresented: $confirmingEnd) {
            if model.session.startedCount > 0 {
                Button("Finish Started Cards (\(model.session.startedCount))") {
                    model.finishUp()
                }
            }
            Button("End Now") { onClose() }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Your answers so far are saved. Cards you haven't finished stay due.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            let session = model.session
            if session.mode == .practice {
                Text("Practice")
                    .font(.headline)
            }
            ProgressView(value: Double(session.completedCount), total: Double(max(session.totalCount, 1)))
                .frame(maxWidth: 320)
            Text("\(session.completedCount) / \(session.totalCount)")
                .monospacedDigit()
            Label("\(session.failedCardIDs.count)", systemImage: "xmark.circle")
                .monospacedDigit()
                .foregroundStyle(session.failedCardIDs.isEmpty ? Color.secondary : Grade.again.color)
                .help("Cards answered wrongly")
            Spacer()
            if !model.isFinished {
                Button("End Session") { confirmingEnd = true }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func cardArea(_ card: Card) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text(card.question)
                .font(.system(size: 32, weight: .semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            if !card.remark.isEmpty {
                Text(card.remark)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Answer", text: $model.input, prompt: Text("Your answer"))
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .focused($answerFocused)
                .disabled(model.stage != .asking)
                .onSubmit { model.submit(undoManager: undoManager) }

            Group {
                if case let .feedback(result, given) = model.stage {
                    FeedbackView(result: result, given: given, expected: card.answer) { grade in
                        model.grade(grade, undoManager: undoManager)
                    }
                } else {
                    Text("Press Return to check your answer.")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 150, alignment: .top)

            Spacer()

            CardStateLine(card: card)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { answerFocused = true }
        .onChange(of: model.stage) { _, stage in
            if stage == .asking { answerFocused = true }
        }
    }
}

/// Result of the check, the correct answer, and the grade buttons.
private struct FeedbackView: View {
    var result: AnswerChecker.Result
    var given: String
    var expected: String
    var onGrade: (Grade) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(result.suggestedGrade.color)

            if result != .correct {
                VStack(spacing: 4) {
                    Text("Correct answer:")
                        .foregroundStyle(.secondary)
                    answerText
                        .font(.title2)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                ForEach(Grade.allCases, id: \.self) { grade in
                    GradeButton(grade: grade, isSuggested: grade == result.suggestedGrade) {
                        onGrade(grade)
                    }
                }
            }

            // Return accepts the suggestion.
            Button("") { onGrade(result.suggestedGrade) }
                .keyboardShortcut(.defaultAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        switch result {
        case .correct: String(localized: "Correct")
        case .incomplete: String(localized: "Correct, but incomplete")
        case .almostCorrect: String(localized: "Almost – check the spelling")
        case .wrong: given.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "Not answered")
            : String(localized: "Wrong")
        }
    }

    private var symbol: String {
        switch result {
        case .correct: "checkmark.circle.fill"
        case .incomplete: "checkmark.circle"
        case .almostCorrect: "exclamationmark.circle"
        case .wrong: "xmark.circle.fill"
        }
    }

    /// The expected answer; for near misses with the differences highlighted.
    private var answerText: Text {
        guard result == .almostCorrect else { return Text(expected) }
        return AnswerDiff.segments(given: given, expected: expected).reduce(Text("")) { text, segment in
            if segment.isMismatch {
                return text + Text(segment.text).bold().underline().foregroundColor(Grade.again.color)
            }
            return text + Text(segment.text)
        }
    }
}

private struct GradeButton: View {
    var grade: Grade
    var isSuggested: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(grade.title)
                    .fontWeight(isSuggested ? .semibold : .regular)
                Text(isSuggested ? "\(grade.rawValue) or ↩" : "\(grade.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 80)
            .padding(.vertical, 2)
        }
        .keyboardShortcut(grade.shortcutKey, modifiers: [])
        .tint(grade.color)
        .buttonStyle(.bordered)
        .overlay {
            if isSuggested {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(grade.color, lineWidth: 2)
            }
        }
    }
}

/// Small line telling where the current card stands.
private struct CardStateLine: View {
    var card: Card

    var body: some View {
        Group {
            if let memory = card.memory {
                switch memory.phase {
                case .review:
                    Text("Review · remembered for \(Format.days(memory.stability))")
                case .learning:
                    Text("Learning")
                case .relearning:
                    Text("Relearning")
                }
            } else {
                Text("New card")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct PreviousAnswerBar: View {
    var previous: StudyViewModel.PreviousAnswer

    var body: some View {
        HStack(spacing: 8) {
            Text("Previous:")
                .foregroundStyle(.secondary)
            Text("\(previous.question) → \(previous.answer)")
                .lineLimit(1)
            Text(previous.grade.title)
                .foregroundStyle(previous.grade.color)
            Spacer()
            Text("⌘Z to undo")
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
