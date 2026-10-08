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
        changed[2] = changed[2].withAnswer("Heim")
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
        changed[0] = changed[0].withAnswer("5")
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
            let question = words.randomElement(using: &random)!
            let answer = words.randomElement(using: &random)!
            var learningState: LearningState?
            if Bool.random(using: &random) {
                learningState = LearningState(
                    phase: .review, stability: .random(in: 0.5...300, using: &random), difficulty: 5,
                    lastReview: Date(), due: Date()
                )
            }
            return Card(question: question, answer: answer, learningState: learningState)
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
                    deck[position] = Card(
                        id: deck[position].id,
                        question: replacement.question,
                        answer: deck[position].answer,
                        learningState: replacement.learningState
                    )
                default:
                    deck.append(makeCard())
                }
            }
            let stepwise = table.rows(of: deck, sortedBy: order, matching: "").map(\.position)
            let full = CardTable().rows(of: deck, sortedBy: order, matching: "").map(\.position)
            try #require(stepwise == full)
        }
    }

    /// Cards edited in place, as by typing in the inspector or by a review, give the
    /// same rows as building the table from scratch (#232).
    @Test(arguments: [
        ([KeyPathComparator(\CardRow.position)], ""),
        ([KeyPathComparator(\CardRow.question)], ""),
        ([KeyPathComparator(\CardRow.answer, order: .reverse)], ""),
        ([KeyPathComparator(\CardRow.question)], "o"),
        ([KeyPathComparator(\CardRow.categoryRank), KeyPathComparator(\CardRow.answer)], "ze"),
    ])
    func editsInPlaceMatchFullRebuild(order: [KeyPathComparator<CardRow>], query: String) throws {
        var random = SeededRandom(seed: 232)
        let words = ["dom", "Dom", "dzień", "dzien", "kot", "Kot", "a", "b", "żaba", "zebra", "10", "9"]
        func word() -> String { words.randomElement(using: &random)! }
        func describe(_ rows: [CardRow]) -> [String] {
            rows.map { "\($0.position) \($0.question) \($0.answer) \($0.hint) \($0.categoryRank)" }
        }

        var deck = (0..<40).map { _ in Card(question: word(), answer: word(), hint: word()) }
        let table = CardTable()
        _ = table.rows(of: deck, sortedBy: order, matching: query)
        for _ in 0..<100 {
            for _ in 0..<Int.random(in: 1...2, using: &random) {
                let position = Int.random(in: deck.indices, using: &random)
                let card = deck[position]
                switch Int.random(in: 0..<4, using: &random) {
                case 0: deck[position] = Card(id: card.id, question: word(), answer: card.answer, hint: card.hint)
                case 1: deck[position] = card.withAnswer(card.answer + word())
                case 2: deck[position] = Card(id: card.id, question: card.question, answer: card.answer, hint: word())
                default:
                    let learningState = LearningState(
                        phase: .review, stability: .random(in: 0.5...300, using: &random), difficulty: 5, lastReview: Date(), due: Date()
                    )
                    deck[position] = Card(id: card.id, question: card.question, answer: card.answer, hint: card.hint, learningState: learningState)
                }
            }
            let stepwise = describe(table.rows(of: deck, sortedBy: order, matching: query))
            let full = describe(CardTable().rows(of: deck, sortedBy: order, matching: query))
            try #require(stepwise == full)
        }
    }

    /// Time of `rows(of:sortedBy:matching:)` per keystroke while the text of one card of
    /// 5000 is typed, as the inspector writes it (#232). Prints the median and has no
    /// time limit. Runs only with `CARD_TABLE_MEASURE` set; through `xcodebuild`, set
    /// `TEST_RUNNER_CARD_TABLE_MEASURE=1`, best with `-configuration Release`.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["CARD_TABLE_MEASURE"] != nil),
        arguments: [("unsorted", [KeyPathComparator(\CardRow.position)], ""), ("by question", [KeyPathComparator(\CardRow.question)], ""), ("by question, search", [KeyPathComparator(\CardRow.question)], "ka")]
    )
    func measureTyping(name: String, order: [KeyPathComparator<CardRow>], query: String) {
        var random = SeededRandom(seed: 232)
        let letters = Array("abcdefghijklmnoprstuwyzłóżćęąś")
        func word() -> String {
            String((0..<Int.random(in: 3...10, using: &random)).map { _ in letters.randomElement(using: &random)! })
        }
        var deck = (0..<5000).map { _ in Card(question: word(), answer: word() + " " + word(), hint: word()) }
        let table = CardTable()
        _ = table.rows(of: deck, sortedBy: order, matching: query)

        var durations: [Duration] = []
        for keystroke in 0..<50 {
            let edited = deck[2500]
            deck[2500] = edited.withAnswer(edited.answer + String(letters[keystroke % letters.count]))
            durations.append(ContinuousClock().measure { _ = table.rows(of: deck, sortedBy: order, matching: query) })
        }
        let median = durations.sorted()[durations.count / 2]
        print("CardTable, 5000 cards, \(name): \(median.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 2)))) per keystroke (median)")
    }
}
