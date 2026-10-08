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

    @Test func replacedEntryFindsNewText() {
        var index = CardSearchIndex(cards: cards)
        index.replace(at: 1, with: Card(question: "chata", answer: "Hütte"))
        #expect(index.positions(matching: "haus").isEmpty)
        #expect(index.positions(matching: "hutte") == [1])
        #expect(index.positions(matching: "a") == [0, 1, 2])
    }

    @Test func ignoresCaseAndDiacritics() {
        let index = CardSearchIndex(cards: cards)
        #expect(index.positions(matching: "DZIEN") == [0])
        #expect(index.positions(matching: "gebaude") == [1])
        #expect(index.positions(matching: "dzien\u{0301}") == [0])  // n + combining acute accent
    }

    @Test func findsDecomposedText() {
        let index = CardSearchIndex(cards: [Card(question: "dzien\u{0301}", answer: "Tag")])
        #expect(index.positions(matching: "dzień") == [0])
    }

    @Test func ignoresStrokes() {
        let index = CardSearchIndex(cards: [Card(question: "łóżko", answer: "Bett"), Card(question: "Łóżko", answer: "Bett")])
        #expect(index.positions(matching: "lozko") == [0, 1])
        #expect(index.positions(matching: "LOZKO") == [0, 1])
    }

    /// Letters that have no canonical decomposition, in lower and upper case, and
    /// their plain spelling.
    @Test(arguments: [
        ("ł", "Ł", "l"), ("ø", "Ø", "o"), ("đ", "Đ", "d"), ("ħ", "Ħ", "h"), ("æ", "Æ", "ae"), ("œ", "Œ", "oe"),
    ])
    func foldsLettersWithoutDecomposition(lower: String, upper: String, plain: String) {
        let index = CardSearchIndex(cards: [
            Card(question: "x\(lower)y", answer: "Tag"),
            Card(question: "x\(upper)y", answer: "Tag"),
            Card(question: "x\(plain)y", answer: "Tag"),
        ])
        for query in ["x\(lower)y", "x\(upper)y", "x\(plain)y", "X\(plain.uppercased())Y"] {
            #expect(index.positions(matching: query) == [0, 1, 2], "query \(query)")
        }
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
