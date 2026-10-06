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
        settle()
    }

    /// Lets SwiftUI update the window.
    private func settle() {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private var fieldEditor: NSTextView? {
        window.firstResponder as? NSTextView
    }

    /// Types `text` and presses Return; the Return is one undo group, like an event.
    private func respond(_ text: String) throws {
        let editor = try #require(fieldEditor)
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
        settle()
        undoManager.beginUndoGrouping()
        editor.insertNewline(nil)
        undoManager.endUndoGrouping()
        settle()
    }

    /// ⌘Z, sent along the responder chain like the menu item.
    private func commandZ() throws {
        let responder = try #require(window.firstResponder)
        #expect(responder.tryToPerform(Selector(("undo:")), with: nil))
        settle()
    }

    @Test func undoAfterContinuingAutomaticallyTakesBackTheReview() throws {
        let first = try #require(model.currentCard)
        try respond(first.answer)
        #expect(document.card(withID: first.id)?.log.count == 1)
        #expect(model.currentCard?.id != first.id)
        #expect(fieldEditor != nil, "the next response field has the focus")

        // Before #9 the first ⌘Z took back the typing of the previous response.
        try commandZ()
        #expect(document.card(withID: first.id)?.log.isEmpty == true)
        #expect(model.currentCard?.id == first.id)
        #expect(model.input.isEmpty)
        window.close()
    }
}
