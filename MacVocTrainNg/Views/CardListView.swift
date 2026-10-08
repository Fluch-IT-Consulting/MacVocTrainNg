import SwiftUI
import VocabCore

struct CardListView: View {
    @ObservedObject var document: VocabularyDocument
    @State private var selection = Set<Card.ID>()
    @State private var sortOrder = [KeyPathComparator(\CardRow.position)]
    @State private var columnCustomization = TableColumnCustomization<CardRow>()
    /// Read only in `sortOrderKeepingFocus` and `focusNewTable`, never in `body`: the
    /// table would lose the click that moves the focus into it (#171).
    @FocusState private var tableIsFocused: Bool
    @State private var searchText = ""
    @State private var showingInspector = false
    @State private var table = CardTable()

    var body: some View {
        // Re-evaluated every minute because cards become due as time passes. The rows
        // stay in `table`, so a tick only formats the visible due dates again. The
        // status bar reads the count of `DueCardCounter`, which ticks at the same time.
        TimelineView(.everyMinute) { _ in
            list(at: document.clock.now)
        }
        .searchable(text: $searchText, prompt: "Search cards")
        .inspector(isPresented: $showingInspector) {
            CardInspector(document: document, selection: selection, onDelete: delete)
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
            .contextMenu(forSelectionType: Card.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Show Details") {
                        selection = ids
                        showingInspector = true
                    }
                    Button("Reset Learning State") {
                        document.resetLearningState(of: ids)
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

            StatusBar(document: document, shownCount: rows.count, isFiltered: !searchText.isEmpty)
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

    /// Sets the sort order and hands the focus of the old table to the new one. A focused
    /// search field keeps its focus.
    ///
    /// `tableIsFocused` is read only here and in `focusNewTable`, never in `body`: a view
    /// that reads it is rebuilt while a click moves the focus into the table, and the
    /// table then loses that click instead of selecting the row (#171).
    private var sortOrderKeepingFocus: Binding<[KeyPathComparator<CardRow>]> {
        Binding {
            sortOrder
        } set: { newOrder in
            // The same order builds no new table, so there is no focus to hand over.
            guard newOrder != sortOrder else { return }
            let tableWasFocused = tableIsFocused
            sortOrder = newOrder
            if tableWasFocused {
                focusNewTable(waitingUntil: .now() + .seconds(1))
            }
        }
    }

    /// Gives the focus to the new table once the old one has left the window and given
    /// the focus up. Asked for earlier, the focus is lost: `tableIsFocused` is still true
    /// for the old table, setting it changes nothing, and SwiftUI drops the request with
    /// that table. The window swaps the tables some time after SwiftUI has built the new
    /// one, at times only after several turns of the run loop (#226).
    private func focusNewTable(waitingUntil deadline: DispatchTime) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            if !tableIsFocused {
                tableIsFocused = true
            } else if .now() < deadline {
                focusNewTable(waitingUntil: deadline)
            }
        }
    }

    private func rows() -> [CardRow] {
        table.rows(of: document.deck.cards, sortedBy: sortOrder, matching: searchText)
    }

    /// Context menu, delete key and inspector all delete through here, so the selection
    /// loses the cards too: `Table` keeps the IDs of removed rows selected (#184).
    private func delete(_ ids: Set<Card.ID>) {
        document.delete(ids)
        selection.subtract(ids)
    }
}

private struct DueText: View {
    var due: Date?
    var now: Date

    var body: some View {
        Text(Format.due(due, now: now))
            .foregroundStyle(due == nil ? .secondary : .primary)
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

    var body: some View {
        let total = document.deck.cards.count
        let due = document.dueCards.count
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
