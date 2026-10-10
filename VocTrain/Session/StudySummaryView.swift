import SwiftUI
import VocabCore

/// Shown when a study session is over.
struct StudySummaryView: View {
    var model: StudyModel
    var onClose: () -> Void

    var body: some View {
        let session = model.session
        let dueCount = model.document.dueCards.count

        List {
            Section {
                LabeledContent("Cards", value: session.completedCount, format: .number)
                LabeledContent("Reviews", value: session.reviewCount, format: .number)
                if session.reviewCount > 0 {
                    LabeledContent("Recalled", value: Format.percent(Double(session.recalledCount) / Double(session.reviewCount)))
                }
                LabeledContent("Mistakes", value: session.mistakeIDs.count, format: .number)
                LabeledContent("Time", value: Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
            } header: {
                Text("Session complete")
            }
            .monospacedDigit()

            Section {
                if dueCount > 0 {
                    Button("Continue (\(dueCount) due)") {
                        model.continueStudying()
                    }
                }
                Button("Done", action: onClose)
            }
        }
    }
}
