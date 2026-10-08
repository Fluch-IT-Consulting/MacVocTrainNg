import SwiftUI
import VocabCore

/// The session screen: asks one card after another.
///
/// Keyboard flow: type the response and press Return. A correct response moves on
/// directly (unless disabled in the preferences). Otherwise the answer is shown
/// and Return accepts the suggested grade; 1–4 choose a grade explicitly, e.g. 3
/// when the response was right after all. ⌘Z takes back the last review.
struct SessionView: View {
    @Bindable var model: SessionViewModel
    var onClose: () -> Void

    /// The question whose response field has the focus.
    @FocusState private var focusedQuestion: Int?
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
                PreviousReviewBar(previous: previous)
            }
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
            Text("Your reviews so far are saved. Cards you haven't finished stay due.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            let session = model.session
            if model.isPracticing {
                Text("Practice")
                    .font(.headline)
            }
            ProgressView(value: Double(session.completedCount), total: Double(max(session.totalCount, 1)))
                .frame(maxWidth: 320)
            Text("\(session.completedCount) / \(session.totalCount)")
                .monospacedDigit()
            Label("\(session.mistakeIDs.count)", systemImage: "xmark.circle")
                .monospacedDigit()
                .foregroundStyle(session.mistakeIDs.isEmpty ? Color.secondary : Grade.again.color)
                .help("Mistakes")
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

            if !card.hint.isEmpty {
                Text(card.hint)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Response", text: $model.input, prompt: Text("Response"))
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .focused($focusedQuestion, equals: model.questionNumber)
                .disabled(model.stage != .asking)
                .onSubmit { model.submit() }
                // Before `id`, so it runs for every new field, not only the first.
                .onAppear { focus(model.questionNumber) }
                // A new field per question: with automatic continuing the field never
                // ends editing, and ⌘Z would first take back the previous typing (#9).
                .id(model.questionNumber)

            Group {
                if case let .feedback(result, response) = model.stage {
                    FeedbackView(result: result, response: response, expected: card.answer, highlightedAnswer: model.highlightedAnswer) { grade in
                        model.grade(grade)
                    }
                } else {
                    Text("Press Return to check your response.")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 150, alignment: .top)

            Spacer()

            CardStateLine(card: card)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Focuses the response field of `question` once the current event is handled.
    /// With automatic continuing the new field appears while the previous one is
    /// still ending its editing; focus set right away got lost there (#75).
    private func focus(_ question: Int) {
        Task { @MainActor in
            focusedQuestion = question
        }
    }
}

/// Check result, the answer, and the grade buttons.
private struct FeedbackView: View {
    var result: CheckResult
    var response: String
    var expected: String
    /// The answer with the differences marked, for almost correct responses.
    var highlightedAnswer: [ResponseDiff.Segment]?
    var onGrade: (Grade) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(result.suggestedGrade.color)

            if result != .correct {
                VStack(spacing: 4) {
                    Text("Answer:")
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
            Button {
                onGrade(result.suggestedGrade)
            } label: {
                Text(verbatim: "")
            }
            .keyboardShortcut(.defaultAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var title: String {
        switch result {
        case .correct: String(localized: "Correct")
        case .incomplete: String(localized: "Incomplete")
        case .almostCorrect: String(localized: "Almost – check the spelling")
        case .wrong:
            response.trimmingCharacters(in: .whitespaces).isEmpty
                ? String(localized: "No response")
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

    /// The answer; for almost correct responses with the differences highlighted.
    private var answerText: Text {
        guard let highlightedAnswer else { return Text(expected) }
        return highlightedAnswer.reduce(Text(verbatim: "")) { text, segment in
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
            if let learningState = card.learningState {
                switch learningState.phase {
                case .review:
                    Text("Review phase · remembered for \(Format.days(learningState.stability))")
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

private struct PreviousReviewBar: View {
    var previous: SessionViewModel.PreviousReview

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
