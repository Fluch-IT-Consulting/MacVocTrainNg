import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

extension WindowTests {
    /// The sheet that edits a card, presented in a real window as the card list presents
    /// it and typed into through the field editor of the sheet's own window.
    @MainActor
    struct CardEditSheetTests {
        let card = Card(question: "blim", answer: "blom")
        let document: VocabularyDocument
        /// Groups by event like in the app: the sheet changes the deck when SwiftUI runs
        /// the action of its button, not inside a group a test could open.
        let undoManager = UndoManager()
        let window: NSWindow
        private let delegate: DocumentWindowDelegate
        private let request = SheetRequest()

        init() {
            document = VocabularyDocument(deck: Deck(cards: [card]))
            document.undoManager = undoManager
            delegate = DocumentWindowDelegate(undoManager: undoManager)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = delegate
            window.contentView = NSHostingView(rootView: SheetPresenter(document: document, request: request))
            // Key for real where the test host is active, as in CI, like the window of a deck.
            window.makeKeyAndOrderFront(nil)
        }

        private var deckCard: Card? {
            document.card(withID: card.id)
        }

        /// Opens the sheet once the window shows its content, as a click would, and returns
        /// it when it shows its fields. In CI (macOS 15), a sheet asked for while the content
        /// first appeared never came.
        private func showSheet() async throws -> NSWindow {
            try await waitUntil("the window shows its content") { request.hasAppeared }
            request.card = card
            try await waitUntil("the sheet is shown") { window.attachedSheet != nil }
            let sheet = try #require(window.attachedSheet)
            try await waitUntil("the sheet shows its three fields") { fields(of: sheet).count == 3 }
            return sheet
        }

        /// The fields question, answer and hint, top to bottom.
        private func fields(of sheet: NSWindow) -> [NSTextField] {
            let fields = sheet.contentView.map { descendants(of: $0).compactMap { $0 as? NSTextField }.filter(\.isEditable) } ?? []
            return fields.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
        }

        /// The default button, Save.
        private func saveButton(of sheet: NSWindow) -> NSButton? {
            sheet.contentView.flatMap { descendants(of: $0).lazy.compactMap { $0 as? NSButton }.first { $0.keyEquivalent == "\r" } }
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        /// Starts editing `field` with the insertion point after its text.
        private func edit(_ field: NSTextField, in sheet: NSWindow) async throws -> NSTextView {
            #expect(sheet.makeFirstResponder(field))
            var editor: NSTextView?
            try await waitUntil("the field is being edited") {
                editor = sheet.firstResponder as? NSTextView
                return (editor?.delegate as? NSTextField) === field
            }
            let fieldEditor = try #require(editor)
            fieldEditor.moveToEndOfDocument(nil)
            return fieldEditor
        }

        /// Types `text` one character per turn, as one event each in the app.
        private func type(_ text: String, into editor: NSTextView) async {
            for character in text {
                editor.insertText(String(character), replacementRange: editor.selectedRange())
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        /// Presses a key in `sheet` the way AppKit offers it to the default and the cancel
        /// button: as a key equivalent, before the field being edited gets it. Returns
        /// whether a button took it.
        private func press(_ key: String, keyCode: UInt16, in sheet: NSWindow) throws -> Bool {
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: sheet.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false,
                    keyCode: keyCode
                )
            )
            return sheet.performKeyEquivalent(with: event)
        }

        private func pressReturn(in sheet: NSWindow) throws -> Bool {
            try press("\r", keyCode: 36, in: sheet)
        }

        private func pressEscape(in sheet: NSWindow) throws -> Bool {
            try press("\u{1B}", keyCode: 53, in: sheet)
        }

        /// ⌘Z, sent along the responder chain like the menu item. Returns whether a
        /// responder took it.
        @discardableResult
        private func commandZ(in sheet: NSWindow) throws -> Bool {
            try #require(sheet.firstResponder).tryToPerform(Selector(("undo:")), with: nil)
        }

        /// Lets the views settle, so a change to the deck on a later turn would show.
        private func settle() async throws {
            try await Task.sleep(for: .milliseconds(200))
        }

        /// Closes a sheet that is still open, then the window.
        private func close() {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.close()
        }

        /// Before #241 the inspector wrote every keystroke to the deck.
        @Test func typingLeavesTheDeckUnchanged() async throws {
            defer { close() }
            let sheet = try await showSheet()
            let editor = try await edit(fields(of: sheet)[1], in: sheet)
            await type("ps", into: editor)
            try await settle()

            #expect(editor.string == "blomps")
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
        }

        @Test func returnSavesTheTextAsOneUndoAction() async throws {
            defer { close() }
            let sheet = try await showSheet()
            let editor = try await edit(fields(of: sheet)[1], in: sheet)
            await type("ps", into: editor)
            try await settle()

            #expect(try pressReturn(in: sheet))
            try await waitUntil("the sheet is closed") { window.attachedSheet == nil }
            #expect(deckCard == card.withAnswer("blomps"))
            #expect(undoManager.undoActionName == "Edit Card" || undoManager.undoActionName == "Karte bearbeiten")

            undoManager.undo()
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
        }

        @Test func escapeCancelsAndLeavesTheDeckUnchanged() async throws {
            defer { close() }
            let sheet = try await showSheet()
            let editor = try await edit(fields(of: sheet)[1], in: sheet)
            await type("ps", into: editor)
            try await settle()

            #expect(try pressEscape(in: sheet))
            try await waitUntil("the sheet is closed") { window.attachedSheet == nil }
            try await settle()
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
        }

        /// Clears the question (0) or the answer (1): Save is disabled, and Return keeps
        /// the sheet open.
        @Test(arguments: [0, 1])
        func saveIsDisabledWhileQuestionOrAnswerIsEmpty(field: Int) async throws {
            defer { close() }
            let sheet = try await showSheet()
            #expect(saveButton(of: sheet)?.isEnabled == true)
            let editor = try await edit(fields(of: sheet)[field], in: sheet)
            editor.selectAll(nil)
            editor.deleteBackward(nil)
            try await waitUntil("Save is disabled") { saveButton(of: sheet)?.isEnabled == false }

            #expect(try !pressReturn(in: sheet))
            try await settle()
            #expect(window.attachedSheet === sheet)
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
        }

        /// The sheet's window has an undo manager of its own (#48): ⌘Z takes back typing,
        /// never a change to the deck.
        @Test func undoInTheSheetTakesBackOnlyTyping() async throws {
            defer { close() }
            document.add(CardText(question: "frax", answer: "frox")!)
            let sheet = try await showSheet()
            let editor = try await edit(fields(of: sheet)[1], in: sheet)
            await type("p", into: editor)
            try await settle()

            #expect(try commandZ(in: sheet))
            try await waitUntil("the typing is taken back") { editor.string == "blom" }
            // Nothing is left to take back in the sheet; the deck keeps its change all the same.
            try commandZ(in: sheet)
            try await settle()
            #expect(document.deck.cards.count == 2)
            #expect(undoManager.canUndo)
        }
    }
}

/// The card a test opens the sheet for, as the card list keeps the one it edits.
@MainActor
@Observable
private final class SheetRequest {
    var card: Card?
    var hasAppeared = false
}

/// Presents the sheet for the card in `request`, the way the card list does.
private struct SheetPresenter: View {
    let document: VocabularyDocument
    @Bindable var request: SheetRequest

    var body: some View {
        Color.clear
            .sheet(item: $request.card) { CardEditSheet(document: document, card: $0) }
            .onAppear { request.hasAppeared = true }
    }
}
