import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VocabCore

/// "Export Cards…": writes the cards of a deck as CSV or TSV, optionally with
/// their learning state in readable columns.
@MainActor
enum CardExport {
    enum Format: String, CaseIterable {
        case csv, tsv

        var contentType: UTType {
            switch self {
            case .csv: .commaSeparatedText
            case .tsv: .tabSeparatedText
            }
        }

        var delimiter: DelimitedText.Delimiter {
            switch self {
            case .csv: .comma
            case .tsv: .tab
            }
        }

        var title: String {
            switch self {
            case .csv: String(localized: "CSV (comma-separated)")
            case .tsv: String(localized: "TSV (tab-separated)")
            }
        }
    }

    /// The table to export: a header row, then one row per card.
    ///
    /// With the learning state, three columns follow: the maturity, the study day
    /// the card is due on (ISO 8601, empty for new cards) and the number of reviews.
    static func rows(of cards: [Card], includingLearningState: Bool, calendar: StudyCalendar) -> [[String]] {
        var header = [String(localized: "Question"), String(localized: "Answer"), String(localized: "Hint")]
        if includingLearningState {
            header += [String(localized: "Maturity"), String(localized: "Due"), String(localized: "Reviews")]
        }
        return [header] + cards.map { card in
            var row = [card.question, card.answer, card.hint]
            if includingLearningState {
                let due = card.learningState.map { CivilDate(dayNumber: calendar.dayNumber(for: $0.due)).isoString }
                row += [MaturityCategory(card: card).title, due ?? "", String(card.learningState?.reviews ?? 0)]
            }
            return row
        }
    }

    /// The file contents: UTF-8 with a byte order mark, which spreadsheets such as
    /// Excel need to recognise the encoding.
    static func data(of cards: [Card], format: Format, includingLearningState: Bool, calendar: StudyCalendar) -> Data {
        let text = DelimitedText.encode(rows(of: cards, includingLearningState: includingLearningState, calendar: calendar), delimiter: format.delimiter)
        return Data(("\u{FEFF}" + text).utf8)
    }

    static func run(cards: [Card], calendar: StudyCalendar, suggestedName: String) {
        let options = Options()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [options.format.contentType]
        savePanel.nameFieldStringValue = suggestedName
        savePanel.message = String(localized: "Export \(cards.count) cards.")
        savePanel.prompt = String(localized: "Export")
        let accessory = NSHostingView(rootView: OptionsView(options: options) { format in
            savePanel.allowedContentTypes = [format.contentType]
        })
        accessory.frame.size = accessory.fittingSize
        savePanel.accessoryView = accessory
        guard savePanel.runModal() == .OK, let target = savePanel.url else { return }

        do {
            try data(of: cards, format: options.format, includingLearningState: options.includesLearningState, calendar: calendar)
                .write(to: target, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Export failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @Observable
    final class Options {
        var format = Format.csv
        var includesLearningState = false
    }

    private struct OptionsView: View {
        @Bindable var options: Options
        var formatChanged: (Format) -> Void

        var body: some View {
            Form {
                Picker("Format:", selection: $options.format) {
                    ForEach(Format.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .fixedSize()
                Toggle("Include learning state", isOn: $options.includesLearningState)
                    .help("Adds the maturity, the day the card is due and the number of reviews.")
            }
            .padding(12)
            .onChange(of: options.format) { _, format in
                formatChanged(format)
            }
        }
    }
}
