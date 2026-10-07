import Foundation
import Testing
import VocabCore

struct DeckChangeTests {
    @Test func addingIsRevertedByTheInverse() {
        let existing = Card(question: "dom", answer: "Haus")
        var deck = Deck(cards: [existing])
        let added = [Card(question: "kot", answer: "Katze"), Card(question: "pies", answer: "Hund")]

        let inverse = deck.apply(DeckChange(upserts: added), day: 100)
        #expect(deck.cards == [existing] + added)

        _ = deck.apply(inverse, day: 100)
        #expect(deck.cards == [existing])
    }

    @Test func replacingIsRevertedByTheInverse() {
        let card = Card(question: "dom", answer: "Haus")
        var deck = Deck(cards: [card, Card(question: "kot", answer: "Katze")])
        var edited = card
        edited.answer = "Haus / Heim"

        let inverse = deck.apply(DeckChange(upserts: [edited]), day: 100)
        #expect(deck.cards[0] == edited)
        #expect(deck.cards.count == 2)

        let redo = deck.apply(inverse, day: 100)
        #expect(deck.cards[0] == card)
        _ = deck.apply(redo, day: 100)
        #expect(deck.cards[0] == edited)
    }

    @Test func removingRestoresOriginalPositions() {
        let cards = (0..<5).map { Card(question: "q\($0)", answer: "a\($0)") }
        var deck = Deck(cards: cards)

        let inverse = deck.apply(DeckChange(removals: [cards[3].id, cards[1].id]), day: 100)
        #expect(deck.cards.map(\.question) == ["q0", "q2", "q4"])

        let redo = deck.apply(inverse, day: 100)
        #expect(deck.cards == cards)
        _ = deck.apply(redo, day: 100)
        #expect(deck.cards.map(\.question) == ["q0", "q2", "q4"])
    }

    @Test func learningOptionsAreRevertedByTheInverse() {
        var deck = Deck(cards: [Card(question: "dom", answer: "Haus")])
        var options = LearningOptions()
        options.steps = 3

        let inverse = deck.apply(DeckChange(learningOptions: options), day: 100)
        #expect(deck.learningOptions == options)

        _ = deck.apply(inverse, day: 100)
        #expect(deck.learningOptions == LearningOptions())
    }

    @Test func changedCardsRecordTheSnapshotOfTheDay() {
        var deck = Deck()
        let card = Card(question: "dom", answer: "Haus")

        let inverse = deck.apply(DeckChange(upserts: [card]), day: 100)
        #expect(deck.progress.map(\.day) == [100])
        #expect(deck.progress.map(\.total) == [1])

        _ = deck.apply(inverse, day: 101)
        #expect(deck.progress.map(\.day) == [100, 101])
        #expect(deck.progress.map(\.total) == [1, 0])
    }

    @Test func learningOptionsAloneRecordNoSnapshot() {
        var deck = Deck(cards: [Card(question: "dom", answer: "Haus")])
        var options = LearningOptions()
        options.steps = 3

        let inverse = deck.apply(DeckChange(learningOptions: options), day: 100)
        _ = deck.apply(inverse, day: 100)
        #expect(deck.progress.isEmpty)
    }

    /// Each change passes over the cards once. Looking up every card on its own took
    /// time quadratic in the number of cards: minutes instead of a fraction of a second.
    @Test(.timeLimit(.minutes(1))) func changesToManyCardsAreRevertedInOneGo() {
        let cards = (0..<10_000).map { Card(question: "q\($0)", answer: "a\($0)") }
        var deck = Deck()

        let undoAdding = deck.apply(DeckChange(upserts: cards), day: 100)
        #expect(deck.cards == cards)

        let edited = cards.map { card in
            var card = card
            card.hint = "h"
            return card
        }
        let undoEditing = deck.apply(DeckChange(upserts: edited), day: 100)
        #expect(deck.cards == edited)

        let removed = Set(cards.indices.filter { $0 % 3 != 0 }.map { cards[$0].id })
        let undoRemoving = deck.apply(DeckChange(removals: Array(removed)), day: 100)
        #expect(deck.cards.map(\.id) == cards.map(\.id).filter { !removed.contains($0) })

        let redoRemoving = deck.apply(undoRemoving, day: 100)
        #expect(deck.cards == edited)
        _ = deck.apply(redoRemoving, day: 100)
        _ = deck.apply(undoRemoving, day: 100)
        _ = deck.apply(undoEditing, day: 100)
        #expect(deck.cards == cards)
        _ = deck.apply(undoAdding, day: 100)
        #expect(deck.cards.isEmpty)
    }
}
