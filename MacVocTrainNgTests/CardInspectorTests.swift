import AppKit
import SwiftUI
import Testing
import VocabCore

@testable import MacVocTrain

extension WindowTests {
    /// The inspector of one card in a real window, typed into through the field editor.
    @MainActor
    struct CardInspectorTests {
        let card = Card(
            question: "blim",
            answer: "blom",
            learningState: LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: Date(), due: Date())
        )
        let document: VocabularyDocument
        /// Groups by event like in the app: the inspector writes to the deck when SwiftUI
        /// updates it, not inside a group a test could open.
        let undoManager = UndoManager()
        let window: NSWindow
        private let delegate: DocumentWindowDelegate

        init() {
            document = VocabularyDocument(deck: Deck(cards: [card]))
            document.undoManager = undoManager
            delegate = DocumentWindowDelegate(undoManager: undoManager)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = delegate
            window.contentView = NSHostingView(rootView: CardInspector(document: document, selection: [card.id], onDelete: { _ in }))
            window.orderFront(nil)
        }

        private var deckCard: Card? {
            document.card(withID: card.id)
        }

        /// The fields question, answer and hint, top to bottom.
        private func fields() async throws -> [NSTextField] {
            var fields: [NSTextField] = []
            try await waitUntil("the inspector shows its fields") {
                fields = window.contentView.map { descendants(of: $0).compactMap { $0 as? NSTextField }.filter(\.isEditable) } ?? []
                return fields.count == 3
            }
            return fields.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }

        /// Starts editing `field` with the insertion point after its text.
        private func edit(_ field: NSTextField) async throws -> NSTextView {
            #expect(window.makeFirstResponder(field))
            var editor: NSTextView?
            try await waitUntil("the field is being edited") {
                editor = window.firstResponder as? NSTextView
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

        @Test func typedTextReachesTheDeckWhileTheFieldKeepsTheFocus() async throws {
            let answer = try await fields()[1]
            let editor = try await edit(answer)
            await type("p", into: editor)

            try await waitUntil("the deck holds the typed answer") { deckCard?.answer == "blomp" }
            #expect(window.firstResponder === editor)
            window.close()
        }

        /// Before #175 a reset copied the card's text back into the fields while one had the focus.
        @Test func resettingTheLearningStateKeepsTheTypedText() async throws {
            let hint = try await fields()[2]
            let editor = try await edit(hint)
            await type("blum ", into: editor)
            try await waitUntil("the deck holds the typed hint") { deckCard?.hint == "blum" }

            document.resetLearningState(of: [card.id])
            try await Task.sleep(for: .milliseconds(100))
            #expect(deckCard?.isNew == true)
            #expect(editor.string == "blum ")

            await type("x", into: editor)
            try await waitUntil("the deck holds the hint typed on") { deckCard?.hint == "blum x" }
            window.close()
        }

        @Test func undoTakesBackAnEditAsOneAction() async throws {
            let answer = try await fields()[1]
            let editor = try await edit(answer)
            await type("ps", into: editor)
            try await waitUntil("the deck holds the typed answer") { deckCard?.answer == "blomps" }
            window.makeFirstResponder(nil)
            try await Task.sleep(for: .milliseconds(50))

            undoManager.undo()
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
            try await waitUntil("the field shows the answer from before") { answer.stringValue == "blom" }
            window.close()
        }

        /// ⌘Z, sent along the responder chain like the menu item.
        private func commandZ() throws {
            let responder = try #require(window.firstResponder)
            #expect(responder.tryToPerform(Selector(("undo:")), with: nil))
        }

        /// Before, the field editor took back the typing first, and the document's undo
        /// action stayed: the deck still counted as changed, the next ⌘Z changed nothing.
        @Test func undoWhileTypingTakesBackTheEditAtOnce() async throws {
            let answer = try await fields()[1]
            let editor = try await edit(answer)
            await type("ps", into: editor)
            try await waitUntil("the deck holds the typed answer") { deckCard?.answer == "blomps" }
            try await Task.sleep(for: .milliseconds(50))

            try commandZ()
            try await waitUntil("the field shows the answer from before") { editor.string == "blom" }
            #expect(deckCard == card)
            #expect(!undoManager.canUndo)
            window.close()
        }

        /// All text fields of the app share one field editor. The next field still undoes
        /// its typing on its own, not with the document's undo manager (#9).
        @Test func theNextFieldKeepsItsOwnTypingUndo() async throws {
            let fields = try await fields()
            let editor = try await edit(fields[1])
            await type("p", into: editor)
            try await waitUntil("the deck holds the typed answer") { deckCard?.answer == "blomp" }
            window.makeFirstResponder(nil)
            try await Task.sleep(for: .milliseconds(50))

            let next = try await edit(fields[2])
            #expect(next.undoManager != nil)
            #expect(next.undoManager !== undoManager)
            window.close()
        }

        @Test func anEmptyQuestionStaysOutOfTheDeck() async throws {
            let question = try await fields()[0]
            let editor = try await edit(question)
            editor.deleteBackward(nil)
            try await waitUntil("the deck holds the shortened question") { deckCard?.question == "bli" }
            editor.selectAll(nil)
            editor.deleteBackward(nil)
            try await Task.sleep(for: .milliseconds(100))
            #expect(deckCard?.question == "bli")

            window.makeFirstResponder(nil)
            try await waitUntil("the field shows the last question the deck took") { question.stringValue == "bli" }
            window.close()
        }
    }
}
