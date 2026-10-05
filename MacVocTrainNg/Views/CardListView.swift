import SwiftUI
import VocabCore

/// One row of the card table, with plain sortable values.
private struct CardRow: Identifiable {
    var id: Card.ID
    var position: Int
    var question: String
    var answer: String
    var remark: String
    var category: MaturityCategory
    var categoryRank: Int
    var dueText: String
    var isNew: Bool
    /// New cards first, then by due date.
    var dueSortKey: Double

    init(card: Card, position: Int, now: Date) {
        id = card.id
        self.position = position
        question = card.question
        answer = card.answer
        remark = card.remark
        category = MaturityCategory(card: card)
        categoryRank = StabilityBins.bin(for: card)
        dueText = Format.due(card, now: now)
        isNew = card.isNew
        dueSortKey = card.memory?.due.timeIntervalSinceReferenceDate ?? -.infinity
    }
}

struct CardListView: View {
    @ObservedObject var document: VocabularyDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selection = Set<Card.ID>()
    @State private var sortOrder = [KeyPathComparator(\CardRow.position)]
    @State private var searchText = ""
    @State private var showingInspector = false

    var body: some View {
        let now = Date()
        let rows = rows(now: now)

        VStack(spacing: 0) {
            AddCardForm(document: document) { id in
                selection = [id]
            }
            .padding(12)

            Divider()

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Question", value: \.question)
                TableColumn("Answer", value: \.answer)
                TableColumn("Hint", value: \.remark)
                TableColumn("Status", value: \.categoryRank) { row in
                    MaturityLabel(category: row.category)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Due", value: \.dueSortKey) { row in
                    Text(row.dueText)
                        .foregroundStyle(row.isNew ? .secondary : .primary)
                }
                .width(min: 80, ideal: 110)
            }
            .contextMenu(forSelectionType: Card.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Show Details") {
                        selection = ids
                        showingInspector = true
                    }
                    Button("Reset Progress") {
                        document.resetProgress(of: ids, undoManager: undoManager)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        delete(ids)
                    }
                }
            } primaryAction: { ids in
                selection = ids
                showingInspector = true
            }
            .onDeleteCommand {
                delete(selection)
            }
            .overlay {
                if rows.isEmpty {
                    emptyState
                }
            }

            Divider()

            StatusBar(document: document, shownCount: rows.count, isFiltered: !searchText.isEmpty, now: now)
        }
        .searchable(text: $searchText, prompt: "Search cards")
        .inspector(isPresented: $showingInspector) {
            CardInspector(document: document, selection: selection)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help("Show or hide card details")
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView(
                "No Cards Yet",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Enter a question and its answer above to add your first card.")
            )
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func rows(now: Date) -> [CardRow] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        var rows: [CardRow] = []
        rows.reserveCapacity(document.deck.cards.count)
        for (position, card) in document.deck.cards.enumerated() {
            if !needle.isEmpty, !card.matches(needle) { continue }
            rows.append(CardRow(card: card, position: position, now: now))
        }
        return rows.sorted(using: sortOrder)
    }

    private func delete(_ ids: Set<Card.ID>) {
        document.delete(ids, undoManager: undoManager)
        selection.subtract(ids)
    }
}

private extension Card {
    /// Case- and diacritic-insensitive search, so "dzien" finds "dzień".
    func matches(_ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return question.range(of: needle, options: options) != nil
            || answer.range(of: needle, options: options) != nil
            || remark.range(of: needle, options: options) != nil
    }
}

struct MaturityLabel: View {
    var category: MaturityCategory

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(category.color)
                .frame(width: 8, height: 8)
            Text(category.title)
        }
        .help(category.explanation)
    }
}

private struct StatusBar: View {
    @ObservedObject var document: VocabularyDocument
    var shownCount: Int
    var isFiltered: Bool
    var now: Date

    var body: some View {
        let total = document.deck.cards.count
        let due = document.dueCount(at: now)
        HStack(spacing: 16) {
            if isFiltered {
                Text("\(shownCount) of \(total) cards")
            } else {
                Text("\(total) cards")
            }
            Text("\(due) due")
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
