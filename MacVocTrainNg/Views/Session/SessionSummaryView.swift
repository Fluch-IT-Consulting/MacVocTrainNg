import SwiftUI
import VocabCore

/// Shown when a session is over.
struct SessionSummaryView: View {
    var model: SessionViewModel
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
                    Text("Reviews")
                        .foregroundStyle(.secondary)
                    Text(session.reviewCount.formatted())
                }
                if session.reviewCount > 0 {
                    GridRow {
                        Text("Recalled")
                            .foregroundStyle(.secondary)
                        Text(Format.percent(Double(session.recalledCount) / Double(session.reviewCount)))
                    }
                }
                GridRow {
                    Text("Mistakes")
                        .foregroundStyle(.secondary)
                    Text(session.mistakeIDs.count.formatted())
                }
                GridRow {
                    Text("Time")
                        .foregroundStyle(.secondary)
                    Text(Duration.seconds(model.document.clock.now.timeIntervalSince(session.startedAt)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                }
            }
            .font(.title3)
            .monospacedDigit()

            HStack(spacing: 12) {
                if !session.mistakeIDs.isEmpty {
                    Button("Practice Mistakes (\(session.mistakeIDs.count))") {
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
