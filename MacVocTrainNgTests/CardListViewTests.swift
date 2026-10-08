import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

/// A window that handles clicks like the key window. The test host can't activate
/// itself, so no window of it becomes key, and the first click into a window that
/// isn't key only makes it key.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

extension WindowTests {
    /// The card list in a real window, sorted through its `NSTableView` and clicked into with
    /// synthetic mouse events.
    @MainActor
    struct CardListViewTests {
        let document = VocabularyDocument(
            deck: Deck(cards: [Card(question: "frax", answer: "frox"), Card(question: "blim", answer: "blom"), Card(question: "glim", answer: "glom")])
        )
        let window: NSWindow

        init() {
            window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CardListView(document: document))
            window.orderFront(nil)
        }

        /// The table of the list; a new sort order replaces it with a new one.
        private var tableView: NSTableView? {
            window.contentView.flatMap { descendants(of: $0).lazy.compactMap { $0 as? NSTableView }.first }
        }

        /// The field "Question" of the form above the table: the leftmost editable text field.
        private var questionField: NSTextField? {
            window.contentView.flatMap { contentView in
                descendants(of: contentView)
                    .compactMap { $0 as? NSTextField }
                    .filter(\.isEditable)
                    .min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            }
        }

        /// The text field being edited, if any.
        private var editedField: NSTextField? {
            (window.firstResponder as? NSTextView)?.delegate as? NSTextField
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        private func showList() async throws -> NSTableView {
            try await waitUntil("the table shows the cards") { tableView?.numberOfRows == 3 }
            return try #require(tableView)
        }

        /// Clicks at `point` of `view`. The mouse-up is queued first: the view tracks the
        /// mouse until it comes.
        private func click(at point: NSPoint, in view: NSView) throws {
            let location = view.convert(point, to: nil)
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try #require(
                    NSEvent.mouseEvent(
                        with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                    )
                )
            }
            let mouseDown = try event(.leftMouseDown)
            NSApp.postEvent(try event(.leftMouseUp), atStart: false)
            window.sendEvent(mouseDown)
        }

        /// Sorts by question like a click on the header of the column: the table tells its
        /// delegate, and `Table` sets its sort order.
        private func sortByQuestion(_ table: NSTableView) throws {
            let prototype = try #require(table.tableColumns.first?.sortDescriptorPrototype)
            table.sortDescriptors = [prototype]
        }

        private func focusQuestionField(_ table: NSTableView) async throws -> NSTextField {
            let field = try #require(questionField)
            #expect(window.makeFirstResponder(field))
            try await waitUntil("the field \"Question\" has the focus") { editedField === field }
            try await updateList(table)
            return field
        }

        /// Adds a card and waits until `table` shows it. The list has then been updated
        /// since the focus last moved and knows where it is. A fixed pause isn't enough:
        /// tests running alongside may keep the main actor busy for longer.
        private func updateList(_ table: NSTableView) async throws {
            let rows = table.numberOfRows
            _ = document.add(try #require(CardText(question: "snirk \(rows)", answer: "snork")), undoManager: nil)
            try await waitUntil("the table shows the added card") { table.numberOfRows == rows + 1 }
        }

        /// Lets the views settle, so a focus handed over on a later turn would show.
        private func settle() async throws {
            try await Task.sleep(for: .milliseconds(200))
        }

        /// A new sort order builds a new table (#168), and it takes the focus of the old one (#170).
        @Test func focusedTableHandsFocusToNewTableWhenSorted() async throws {
            defer { window.close() }
            let table = try await showList()
            #expect(window.makeFirstResponder(table))
            try await updateList(table)

            try sortByQuestion(table)
            try await waitUntil("a new table replaces the old one") { tableView.map { $0 !== table } ?? false }
            try await waitUntil("the new table has the focus") { tableView.map { window.firstResponder === $0 } ?? false }
        }

        @Test func focusedQuestionFieldKeepsFocusWhenSorted() async throws {
            defer { window.close() }
            let table = try await showList()
            let field = try await focusQuestionField(table)

            try sortByQuestion(table)
            try await waitUntil("a new table replaces the old one") { tableView.map { $0 !== table } ?? false }
            try await settle()
            #expect(editedField === field)
        }

        /// Before #171 the table lost the click that moved the focus into it.
        @Test func firstClickIntoTableSelectsRow() async throws {
            defer { window.close() }
            let table = try await showList()
            _ = try await focusQuestionField(table)

            let rect = table.rect(ofRow: 1)
            try click(at: NSPoint(x: rect.midX, y: rect.midY), in: table)
            try await waitUntil("the row is selected") { table.selectedRowIndexes == [1] }
            #expect(window.firstResponder === table)
        }
    }
}
