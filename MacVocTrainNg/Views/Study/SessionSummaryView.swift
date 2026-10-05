import SwiftUI
import VocabCore

/// Shown when a session is over.
struct SessionSummaryView: View {
    var model: StudyViewModel
    var onClose: () -> Void

    var body: some View {
        let session = model.session
        let dueCount = model.document.dueCount()

        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text(session.mode == .practice ? "Practice complete" : "Session complete")
                .font(.largeTitle.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Cards")
                        .foregroundStyle(.secondary)
                    Text(session.completedCount.formatted())
                }
                GridRow {
                    Text("Answers")
                        .foregroundStyle(.secondary)
                    Text(session.answerCount.formatted())
                }
                if session.answerCount > 0 {
                    GridRow {
                        Text("Correct")
                            .foregroundStyle(.secondary)
                        Text(Format.percent(Double(session.correctCount) / Double(session.answerCount)))
                    }
                }
                GridRow {
                    Text("Mistakes")
                        .foregroundStyle(.secondary)
                    Text(session.failedCardIDs.count.formatted())
                }
                GridRow {
                    Text("Time")
                        .foregroundStyle(.secondary)
                    Text(Duration.seconds(Date().timeIntervalSince(session.startedAt)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                }
            }
            .font(.title3)
            .monospacedDigit()

            HStack(spacing: 12) {
                if !session.failedCardIDs.isEmpty {
                    Button("Practice Mistakes (\(session.failedCardIDs.count))") {
                        model.practiceMistakes()
                    }
                }
                if dueCount > 0 {
                    Button("Continue (\(dueCount) due)") {
                        model.continueStudying()
                    }
                }
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
