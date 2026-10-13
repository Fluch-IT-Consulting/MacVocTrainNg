import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

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
            // The window has no `DocumentView` to give the document its undo manager.
            undoManager = makeUndoManager(for: document)
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

        /// Presses ⌘E in the window the way AppKit offers it to a button's shortcut, as
        /// a key equivalent. Returns whether a button took it.
        private func pressCommandE() throws -> Bool {
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false,
                    keyCode: 14
                )
            )
            return window.performKeyEquivalent(with: event)
        }

        /// Opens the sheet that edits the card being asked and returns it once it shows
        /// `fieldCount` fields.
        private func showEditSheet(fieldCount: Int) async throws -> NSWindow {
            #expect(try pressCommandE())
            try await waitUntil("the sheet is shown") { window.attachedSheet != nil }
            let sheet = try #require(window.attachedSheet)
            try await waitUntil("the sheet shows \(fieldCount) fields") { editableFields(in: sheet).count == fieldCount }
            return sheet
        }

        /// The fields of the sheet, top to bottom.
        private func editableFields(in sheet: NSWindow) -> [NSTextField] {
            let fields = sheet.contentView.map { descendants(of: $0).compactMap { $0 as? NSTextField }.filter(\.isEditable) } ?? []
            return fields.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        /// Before the response is checked, the sheet shows question and hint but not the
        /// answer (#289).
        @Test func editingWhileAskingHidesTheAnswer() async throws {
            defer { window.close() }
            let card = try #require(model.currentCard)
            try await waitUntil("the first response field has the focus") { editedField != nil }

            let sheet = try await showEditSheet(fieldCount: 2)
            #expect(editableFields(in: sheet).map(\.stringValue) == [card.question, card.hint])
            window.endSheet(sheet)
        }

        /// Once the answer is shown, the sheet edits it too (#289).
        @Test func editingTheShownAnswer() async throws {
            defer { window.close() }
            let card = try #require(model.currentCard)
            try await waitUntil("the first response field has the focus") { editedField != nil }
            try await respond("wrong")
            try await waitUntil("the answer is shown") { model.stage != .asking }

            let sheet = try await showEditSheet(fieldCount: 3)
            #expect(editableFields(in: sheet).contains { $0.stringValue == card.answer })
            window.endSheet(sheet)
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
