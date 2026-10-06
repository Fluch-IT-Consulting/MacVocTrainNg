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

    @Test func equalValuesKeepDeckOrder() {
        let twins = [
            Card(question: "b", answer: "1"),
            Card(question: "a", answer: "2"),
            Card(question: "b", answer: "3"),
            Card(question: "a", answer: "4"),
        ]
        let table = CardTable()
        #expect(table.rows(of: twins, sortedBy: byQuestion, matching: "").map(\.answer) == ["2", "4", "1", "3"])

        var changed = twins
        changed[0].answer = "5"
        changed.insert(Card(question: "a", answer: "6"), at: 0)
        #expect(table.rows(of: changed, sortedBy: byQuestion, matching: "").map(\.answer) == ["6", "2", "4", "5", "3"])
    }

    @Test func undoneDeletionReturnsToItsPlace() {
        let table = CardTable()
        _ = table.rows(of: cards, sortedBy: byQuestion, matching: "")
        _ = table.rows(of: [cards[0], cards[2]], sortedBy: byQuestion, matching: "")
        #expect(table.rows(of: cards, sortedBy: byQuestion, matching: "").map(\.position) == [2, 1, 0])
    }

    /// Edits, insertions and removals sorted in step by step give the same rows as
    /// sorting from scratch.
    @Test(arguments: [
        [KeyPathComparator(\CardRow.question)],
        [KeyPathComparator(\CardRow.answer, order: .reverse)],
        [KeyPathComparator(\CardRow.categoryRank), KeyPathComparator(\CardRow.question)],
        [KeyPathComparator(\CardRow.position, order: .reverse)],
    ])
    func stepwiseSortingMatchesFullSort(order: [KeyPathComparator<CardRow>]) throws {
        var random = SeededRandom(seed: 21)
        let words = ["dom", "Dom", "dzień", "dzien", "kot", "Kot", "a", "b", "żaba", "zebra", "10", "9"]
        func makeCard() -> Card {
            var card = Card(question: words.randomElement(using: &random)!, answer: words.randomElement(using: &random)!)
            if Bool.random(using: &random) {
                card.learningState = LearningState(
                    phase: .review, stability: .random(in: 0.5...300, using: &random), difficulty: 5,
                    lastReview: Date(), due: Date()
                )
            }
            return card
        }

        var deck = (0..<40).map { _ in makeCard() }
        let table = CardTable()
        _ = table.rows(of: deck, sortedBy: order, matching: "")
        for _ in 0..<100 {
            for _ in 0..<Int.random(in: 1...3, using: &random) {
                switch Int.random(in: 0..<4, using: &random) {
                case 0 where !deck.isEmpty:
                    deck.remove(at: Int.random(in: deck.indices, using: &random))
                case 1:
                    deck.insert(makeCard(), at: Int.random(in: 0...deck.count, using: &random))
                case 2 where !deck.isEmpty:
                    let position = Int.random(in: deck.indices, using: &random)
                    let replacement = makeCard()
                    deck[position].question = replacement.question
                    deck[position].learningState = replacement.learningState
                default:
                    deck.append(makeCard())
                }
            }
            let stepwise = table.rows(of: deck, sortedBy: order, matching: "").map(\.position)
            let full = CardTable().rows(of: deck, sortedBy: order, matching: "").map(\.position)
            try #require(stepwise == full)
        }
    }
}
