import SwiftUI
import VocabCore

/// Learning options stored in the deck.
struct DeckOptionsView: View {
    @ObservedObject var document: VocabularyDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var settings: DeckSettings

    init(document: VocabularyDocument) {
        self.document = document
        _settings = State(initialValue: document.deck.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Target recall") {
                        HStack {
                            Slider(value: $settings.desiredRetention, in: DeckSettings.retentionRange, step: 0.01)
                            Text(Format.percent(settings.desiredRetention))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Scheduling")
                } footer: {
                    Text("Cards in the review phase are asked again when their recall probability drops to this value. Higher means more reviews but fewer lapses; 90 % is a good balance.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    LimitField(title: "Cards per session", value: $settings.cardsPerSession, defaultValue: 100, step: 10)
                    LimitField(title: "New cards per session", value: $settings.newCardsPerSession, defaultValue: 20, step: 5)
                    Stepper(value: $settings.learningSteps, in: DeckSettings.learningStepsRange) {
                        LabeledContent("Steps per card", value: settings.learningSteps.formatted())
                    }
                } header: {
                    Text("Sessions")
                } footer: {
                    Text("New cards and cards after a lapse come back within the session until they have been graded Good this many times. Hard keeps a card on its step, Again resets it, Easy moves it to the review phase at once.")
                        .foregroundStyle(.secondary)
                }

                Section("Checking") {
                    Toggle("Case-sensitive", isOn: $settings.caseSensitive)
                }

                Section("Advanced") {
                    Toggle("Spread out intervals", isOn: $settings.fuzzing)
                        .help("Varies intervals slightly so cards learned together don't always come back together.")
                    Stepper(value: $settings.maximumInterval, in: 30...36500, step: 30) {
                        LabeledContent("Longest interval", value: Format.days(Double(settings.maximumInterval)))
                    }
                    if settings.parameters != .default {
                        Button("Reset Algorithm Parameters") {
                            settings.parameters = .default
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Restore Defaults") {
                    settings = DeckSettings()
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    document.updateSettings(settings, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}

/// A number with an "unlimited" option.
private struct LimitField: View {
    var title: LocalizedStringKey
    @Binding var value: Int?
    var defaultValue: Int
    var step: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let limit = value {
                    // A stepper rather than a text field: a text field only commits on
                    // Return, so clicking Save right after typing would lose the value.
                    Stepper(value: Binding(get: { limit }, set: { value = $0 }), in: 1...9999, step: step) {
                        Text(limit.formatted())
                            .monospacedDigit()
                    }
                }
                Toggle("Unlimited", isOn: Binding(
                    get: { value == nil },
                    set: { value = $0 ? nil : defaultValue }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}
