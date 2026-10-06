import Foundation
import Testing
@testable import VocabCore

struct CardSearchIndexTests {
    let cards = [
        Card(question: "dzień", answer: "Tag"),
        Card(question: "dom", answer: "Haus", hint: "Gebäude"),
        Card(question: "kot", answer: "Katze"),
    ]

    @Test func searchesQuestionAnswerAndHint() {
        let index = CardSearchIndex(cards: cards)
        #expect(index.positions(matching: "dzie") == [0])
        #expect(index.positions(matching: "katz") == [2])
        #expect(index.positions(matching: "gebäude") == [1])
    }

    @Test func ignoresCaseAndDiacritics() {
        let index = CardSearchIndex(cards: cards)
        #expect(index.positions(matching: "DZIEN") == [0])
        #expect(index.positions(matching: "gebaude") == [1])
        #expect(index.positions(matching: "dzien\u{0301}") == [0]) // n + combining acute accent
    }

    @Test func findsDecomposedText() {
        let index = CardSearchIndex(cards: [Card(question: "dzien\u{0301}", answer: "Tag")])
        #expect(index.positions(matching: "dzień") == [0])
    }

    @Test func blankQueryMatchesEverything() {
        let index = CardSearchIndex(cards: cards)
        #expect(index.positions(matching: "") == [0, 1, 2])
        #expect(index.positions(matching: "  ") == [0, 1, 2])
    }

    @Test func queryIsTrimmed() {
        #expect(CardSearchIndex(cards: cards).positions(matching: " kot ") == [2])
    }

    @Test func doesNotMatchAcrossFields() {
        #expect(CardSearchIndex(cards: cards).positions(matching: "domhaus").isEmpty)
        #expect(CardSearchIndex(cards: cards).positions(matching: "kotkatze").isEmpty)
    }

    @Test func filterKeepsTheGivenOrder() {
        let index = CardSearchIndex(cards: cards)
        #expect(index.filter([2, 1, 0], by: "a") == [2, 1, 0])
        #expect(index.filter([2, 0], by: "o") == [2])
    }
}
