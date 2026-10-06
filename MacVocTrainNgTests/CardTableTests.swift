import Foundation
import Testing
import VocabCore
@testable import MacVocTrain

@MainActor
struct CardTableTests {
    let cards = [
        Card(question: "kot", answer: "Katze"),
        Card(question: "dzień", answer: "Tag"),
        Card(question: "dom", answer: "Haus"),
    ]
    let deckOrder = [KeyPathComparator(\CardRow.position)]
    let byQuestion = [KeyPathComparator(\CardRow.question)]

    @Test func keepsDeckOrderByDefault() {
        let rows = CardTable().rows(of: cards, sortedBy: deckOrder, matching: "")
        #expect(rows.map(\.question) == ["kot", "dzień", "dom"])
        #expect(rows.map(\.position) == [0, 1, 2])
    }

    @Test func searchKeepsTheSortOrder() {
        let table = CardTable()
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "").map(\.question) == ["dom", "dzień", "kot"])
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "d").map(\.question) == ["dom", "dzień"])
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "DZIEN").map(\.question) == ["dzień"])
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "").count == 3)
    }

    @Test func followsChangedSortOrder() {
        let table = CardTable()
        _ = table.rows(of: cards, sortedBy: byQuestion, matching: "")
        let reversed = [KeyPathComparator(\CardRow.question, order: .reverse)]
        #expect(table.rows(of: cards, sortedBy: reversed, matching: "").map(\.question) == ["kot", "dzień", "dom"])
        #expect(table.rows(of: cards, sortedBy: deckOrder, matching: "").map(\.question) == ["kot", "dzień", "dom"])
    }

    @Test func followsChangedCards() {
        let table = CardTable()
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "haus").map(\.question) == ["dom"])

        var changed = cards
        changed[2].answer = "Heim"
        changed.append(Card(question: "chata", answer: "Haus"))
        #expect(table.rows(of: changed, sortedBy: byQuestion, matching: "haus").map(\.question) == ["chata"])
        #expect(table.rows(of: changed, sortedBy: byQuestion, matching: "").map(\.position) == [3, 2, 1, 0])
    }
}
