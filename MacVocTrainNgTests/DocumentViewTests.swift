import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

extension WindowTests {
    /// The content of a document window in a real window, typed into through the field editor.
    @MainActor
    struct DocumentViewTests {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "frax", answer: "frox")]))
        let undoManager: UndoManager
        let window: NSWindow
        private let delegate: DocumentWindowDelegate

        init() {
            // `DocumentView` gives the document the undo manager of the window.
            undoManager = UndoManager()
            delegate = DocumentWindowDelegate(undoManager: undoManager)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = delegate
        }

        private func show(isEditable: Bool) {
            window.contentView = NSHostingView(rootView: DocumentView(document: document, fileURL: nil, isEditable: isEditable))
            window.orderFront(nil)
        }

        /// The fields of the form for adding cards, left to right: the topmost text fields.
        private func formFields() async throws -> [NSTextField] {
            var fields: [NSTextField] = []
            try await waitUntil("the form shows its fields") {
                let all = window.contentView.map { descendants(of: $0).compactMap { $0 as? NSTextField }.filter(\.isEditable) } ?? []
                let top = all.map { $0.convert($0.bounds, to: nil).maxY }.max()
                fields = all.filter { $0.convert($0.bounds, to: nil).maxY == top }
                return fields.count == 3
            }
            return fields.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        /// Types `text` into `field` if the field takes the focus.
        private func type(_ text: String, into field: NSTextField) async throws {
            guard window.makeFirstResponder(field), let editor = window.firstResponder as? NSTextView else { return }
            editor.insertText(text, replacementRange: editor.selectedRange())
            try await waitUntil("the field holds the text") { field.stringValue == text }
            // The form reads its text from the view's state, which follows the field
            // on a later turn.
            try await Task.sleep(for: .milliseconds(100))
        }

        /// Types a question and an answer into the form and presses Return, as when adding a card.
        @Test(arguments: [true, false])
        func formAddsCardOnlyToEditableDeck(isEditable: Bool) async throws {
            defer { window.close() }
            show(isEditable: isEditable)
            let fields = try await formFields()
            #expect(fields.allSatisfy { $0.isEnabled == isEditable })

            try await type("blim", into: fields[0])
            try await type("blom", into: fields[1])
            (window.firstResponder as? NSTextView)?.insertNewline(nil)
            try await Task.sleep(for: .milliseconds(200))

            #expect(document.deck.cards.count == (isEditable ? 2 : 1))
            #expect(undoManager.canUndo == isEditable)
        }
    }
}
