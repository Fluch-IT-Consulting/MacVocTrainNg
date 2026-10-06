import SwiftUI
import VocabCore

/// The cards of an import file, to choose which ones to add to the deck.
struct ImportPreviewView: View {
    @ObservedObject var document: VocabularyDocument
    @Bindable var preview: CardImport.Preview
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Cards")
                    .font(.title2.weight(.semibold))
                Text("\(preview.candidates.count) cards in “\(preview.fileName)”")
                    .foregroundStyle(.secondary)
                if preview.skippedRows > 0 {
                    Text("\(preview.skippedRows) rows without a question or an answer are left out.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Table(preview.candidates) {
                TableColumn(Text(verbatim: "")) { candidate in
                    Toggle("Import", isOn: isSelected(candidate.id))
                        .labelsHidden()
                }
                .width(20)
                TableColumn("Question", value: \.card.question)
                TableColumn("Answer", value: \.card.answer)
                TableColumn("Hint", value: \.card.hint)
                TableColumn("Note") { candidate in
                    switch candidate.duplicate {
                    case .inDeck:
                        Label("Already in this deck", systemImage: "exclamationmark.triangle")
                    case let .inFile(row):
                        Label("Already in row \(row)", systemImage: "exclamationmark.triangle")
                    case nil:
                        EmptyView()
                    }
                }
                .width(min: 120, ideal: 160)
            }

            Divider()

            HStack {
                Button("Select All") {
                    preview.selection = Set(preview.candidates.map(\.id))
                }
                Button("Select None") {
                    preview.selection = []
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(preview.selection.count) Cards") {
                    document.importCards(preview.selectedCards, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.selection.isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 440, idealHeight: 540)
    }

    private func isSelected(_ id: Card.ID) -> Binding<Bool> {
        Binding(
            get: { preview.selection.contains(id) },
            set: { isOn in
                if isOn {
                    preview.selection.insert(id)
                } else {
                    preview.selection.remove(id)
                }
            }
        )
    }
}
