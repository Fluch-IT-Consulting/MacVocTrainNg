import SwiftUI
import VocabCore

/// The FSRS parameters in the learning options: computes them from the deck's review
/// log and compares them with the current ones. Saving the options applies them.
struct ParametersSection: View {
    @Binding var options: LearningOptions
    let cards: [Card]
    let calendar: StudyCalendar

    /// Counted once per opening of the sheet, not in `init`: the parent rebuilds this
    /// view on every change to the options, and counting goes through the whole log.
    @State private var reviewCount: Int?
    @State private var state = ComputationState.idle
    @State private var task: Task<Void, Never>?

    private enum ComputationState {
        case idle
        case running(Double)
        case finished(Comparison)
        case failed
    }

    struct Comparison: Sendable {
        var parameters: FSRSParameters
        var current: FSRSOptimizer.Evaluation
        var computed: FSRSOptimizer.Evaluation

        var isBetter: Bool { computed.logLoss < current.logLoss }
    }

    var body: some View {
        Section {
            LabeledContent("Current parameters", value: options.parameters == .default ? String(localized: "Default") : String(localized: "Custom"))
                // On a row that is always there, whatever the count.
                .task { await countReviews() }
            switch reviewCount {
            case nil:
                LabeledContent("Usable reviews", value: "")
            case let count? where count < FSRSOptimizer.minimumReviewCount:
                LabeledContent("Usable reviews", value: "\(count) / \(FSRSOptimizer.minimumReviewCount)")
            case let count?:
                LabeledContent("Usable reviews", value: count.formatted())
                computation
            }
            if options.parameters != .default {
                Button("Reset Algorithm Parameters") {
                    options.parameters = .default
                }
            }
        } header: {
            Text("Algorithm Parameters")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("FSRS starts with parameters averaged over many learners. Computed from this deck's review log, they fit your memory, so cards need fewer reviews for the same target recall. Cards keep their due dates; new intervals apply from their next review.")
                if let reviewCount, reviewCount < FSRSOptimizer.minimumReviewCount {
                    Text("Computing needs \(FSRSOptimizer.minimumReviewCount) usable reviews: reviews on a later study day than the previous review of the same card.")
                }
            }
            .foregroundStyle(.secondary)
        }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var computation: some View {
        switch state {
        case .idle:
            Button("Compute from Review Log", action: start)
        case .running(let fraction):
            HStack {
                ProgressView(value: fraction)
                Button("Cancel") { task?.cancel() }
            }
        case .finished(let comparison):
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Current").foregroundStyle(.secondary)
                    Text("New").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Prediction error").gridColumnAlignment(.leading)
                    Text(Self.error(comparison.current.rmse))
                    Text(Self.error(comparison.computed.rmse))
                }
                GridRow {
                    Text("Log loss")
                    Text(Self.loss(comparison.current.logLoss))
                    Text(Self.loss(comparison.computed.logLoss))
                }
            }
            .monospacedDigit()
            if !comparison.isBetter {
                Text("The current parameters already predict your reviews best.")
            } else if options.parameters == comparison.parameters {
                Label("Takes effect when you save.", systemImage: "checkmark.circle")
            } else {
                Button("Use New Parameters") {
                    options.parameters = comparison.parameters
                }
            }
        case .failed:
            Text("The parameters could not be computed.")
            Button("Compute from Review Log", action: start)
        }
    }

    private static func error(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private static func loss(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }

    private func countReviews() async {
        // The form may create the row again after scrolling it out of view.
        guard reviewCount == nil else { return }
        let cards = cards
        let calendar = calendar
        let options = options
        reviewCount = await Task.detached(priority: .userInitiated) {
            FSRSOptimizer(cards: cards, learningOptions: options, calendar: calendar).reviewCount
        }.value
    }

    private func start() {
        let optimizer = FSRSOptimizer(cards: cards, learningOptions: options, calendar: calendar)
        let current = options.parameters
        state = .running(0)
        task = Task {
            let (progress, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
            let work = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                let parameters = try optimizer.computeParameters { continuation.yield($0) }
                guard let before = optimizer.evaluate(current), let after = optimizer.evaluate(parameters) else {
                    throw FSRSOptimizer.Error.notEnoughData
                }
                return Comparison(parameters: parameters, current: before, computed: after)
            }
            await withTaskCancellationHandler {
                for await fraction in progress {
                    state = .running(fraction)
                }
            } onCancel: {
                work.cancel()
            }
            switch await work.result {
            case .success(let comparison): state = .finished(comparison)
            case .failure(is CancellationError): state = .idle
            case .failure: state = .failed
            }
        }
    }
}
