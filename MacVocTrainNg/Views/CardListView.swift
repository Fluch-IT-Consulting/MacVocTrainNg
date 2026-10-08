import SwiftUI
import VocabCore

struct CardListView: View {
    @ObservedObject var document: VocabularyDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selection = Set<Card.ID>()
    @State private var sortOrder = [KeyPathComparator(\CardRow.position)]
    @State private var columnCustomization = TableColumnCustomization<CardRow>()
    @FocusState private var tableIsFocused: Bool
    @State private var refocusTable = false
    @State private var searchText = ""
    @State private var showingInspector = false
    @State private var table = CardTable()

    var body: some View {
        // Re-evaluated every minute because cards become due as time passes. The rows
        // stay in `table`, so a tick only counts the due cards and formats the visible
        // due dates again.
        TimelineView(.everyMinute) { _ in
            list(at: document.clock.now)
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

    private func list(at now: Date) -> some View {
        let rows = rows()

        return VStack(spacing: 0) {
            AddCardForm(document: document) { id in
                selection = [id]
            }
            .padding(12)

            Divider()

            Table(rows, selection: $selection, sortOrder: sortOrderKeepingFocus, columnCustomization: $columnCustomization) {
                TableColumn("Question", value: \.question)
                    .customizationID("question")
                    .disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn("Answer", value: \.answer)
                    .customizationID("answer")
                    .disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn("Hint", value: \.hint)
                    .customizationID("hint")
                    .disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn("Maturity", value: \.categoryRank) { row in
                    MaturityLabel(category: row.category)
                }
                .width(min: 90, ideal: 110)
                .customizationID("maturity")
                .disabledCustomizationBehavior([.reorder, .visibility])
                TableColumn("Due", value: \.dueSortKey) { row in
                    // Formatted per visible cell rather than for all rows up front.
                    DueText(due: row.due, now: now)
                }
                .width(min: 80, ideal: 110)
                .customizationID("due")
                .disabledCustomizationBehavior([.reorder, .visibility])
            }
            .focused($tableIsFocused)
            // A new sort order builds a new table: diffing the old order against the
            // new one moves every row on its own, which is slow with many cards (#168).
            // The column widths live in `columnCustomization`, and the focus moves over
            // through `sortOrderKeepingFocus`.
            .id(sortOrder)
            .onChange(of: tableIsFocused) { _, isFocused in
                // The new table can take the focus only after the old one has given it
                // up, and only on the next turn of the run loop.
                if !isFocused && refocusTable {
                    refocusTable = false
                    DispatchQueue.main.async {
                        tableIsFocused = true
                    }
                }
            }
            .contextMenu(forSelectionType: Card.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Show Details") {
                        selection = ids
                        showingInspector = true
                    }
                    Button("Reset Learning State") {
                        document.resetLearningState(of: ids, undoManager: undoManager)
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

    /// Sets the sort order and hands the focus of the old table to the new one, see
    /// `onChange(of: tableIsFocused)`. A focused search field keeps its focus.
    private var sortOrderKeepingFocus: Binding<[KeyPathComparator<CardRow>]> {
        Binding {
            sortOrder
        } set: { newOrder in
            // The same order builds no new table, so there is no focus to hand over.
            guard newOrder != sortOrder else { return }
            refocusTable = tableIsFocused
            sortOrder = newOrder
        }
    }

    private func rows() -> [CardRow] {
        table.rows(of: document.deck.cards, sortedBy: sortOrder, matching: searchText)
    }

    private func delete(_ ids: Set<Card.ID>) {
        document.delete(ids, undoManager: undoManager)
        selection.subtract(ids)
    }
}

private struct DueText: View {
    var due: Date?
    var now: Date

    var body: some View {
        if let due {
            Text(due <= now ? String(localized: "Now") : due.formatted(.relative(presentation: .named)))
        } else {
            Text("New")
                .foregroundStyle(.secondary)
        }
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
        let due = document.deck.dueCount(at: now)
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
