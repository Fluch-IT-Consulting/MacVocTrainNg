import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

/// Gives the window the undo manager a document window gets from its document.
@MainActor
private final class DocumentWindowDelegate: NSObject, NSWindowDelegate {
    let undoManager: UndoManager

    init(undoManager: UndoManager) {
        self.undoManager = undoManager
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }
}

extension WindowTests {
    /// The session screen in a real window, typed into through the field editor.
    @MainActor
    struct SessionViewTests {
        let document = VocabularyDocument(deck: Deck(cards: [Card(question: "blim", answer: "blom"), Card(question: "frax", answer: "frox")]))
        let undoManager: UndoManager
        let model: SessionViewModel
        let window: NSWindow
        private let delegate: DocumentWindowDelegate

        init() {
            undoManager = UndoManager()
            undoManager.groupsByEvent = false
            model = SessionViewModel(document: document, autoAdvance: true)
            delegate = DocumentWindowDelegate(undoManager: undoManager)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = delegate
            window.contentView = NSHostingView(rootView: SessionView(model: model, onClose: {}))
            window.orderFront(nil)
        }

        private var fieldEditor: NSTextView? {
            window.firstResponder as? NSTextView
        }

        /// The response field being edited, if any.
        private var editedField: NSTextField? {
            fieldEditor?.delegate as? NSTextField
        }

        /// Types `text` and presses Return; the Return is one undo group, like an event.
        private func respond(_ text: String) async throws {
            let editor = try #require(fieldEditor)
            for character in text {
                editor.insertText(String(character), replacementRange: editor.selectedRange())
            }
            try await waitUntil("the model holds the response") { model.input == text }
            // Return is an event of its own: the views finish handling the typing first.
            // Pressed in the same turn, the review isn't what ⌘Z takes back.
            await Task.yield()
            undoManager.beginUndoGrouping()
            editor.insertNewline(nil)
            undoManager.endUndoGrouping()
        }

        /// ⌘Z, sent along the responder chain like the menu item.
        private func commandZ() throws {
            let responder = try #require(window.firstResponder)
            #expect(responder.tryToPerform(Selector(("undo:")), with: nil))
        }

        @Test func undoAfterContinuingAutomaticallyTakesBackTheReview() async throws {
            let first = try #require(model.currentCard)
            try await waitUntil("the first response field has the focus") { editedField != nil }
            let firstField = try #require(editedField)
            try await respond(first.answer)
            try await waitUntil("the next response field has the focus") { editedField.map { $0 !== firstField } ?? false }
            #expect(document.card(withID: first.id)?.log.count == 1)
            #expect(model.currentCard?.id != first.id)
            #expect(editedField?.window === window)

            // Before #9 the first ⌘Z took back the typing of the previous response.
            try commandZ()
            try await waitUntil("the review is taken back") { model.currentCard?.id == first.id }
            #expect(document.card(withID: first.id)?.log.isEmpty == true)
            #expect(model.currentCard?.id == first.id)
            #expect(model.input.isEmpty)
            window.close()
        }
    }
}
