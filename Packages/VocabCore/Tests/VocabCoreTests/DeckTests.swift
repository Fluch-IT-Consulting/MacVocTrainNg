import Foundation
import Testing

@testable import VocabCore

/// Building a deck from its parts, as `DeckFile` and `LegacyImporter` do (#306).
struct DeckTests {
    private let date = Date(timeIntervalSince1970: 1_791_216_000)

    @Test func emptyDeckHasTheDefaultOptions() {
        let deck = Deck()
        #expect(deck.cards.isEmpty)
        #expect(deck.progress.isEmpty)
        #expect(deck.contentModified == nil)
        #expect(deck.learningOptions == LearningOptions())
    }

    @Test func validPartsAreKeptInTheirOrder() throws {
        let cards = [Card(question: "pies", answer: "Hund"), Card(question: "dom", answer: "Haus"), Card(question: "kot", answer: "Katze")]
        var options = LearningOptions()
        options.steps = 3
        let progress = [DailySnapshot(day: 20_000, bins: [3])]

        let deck = try Deck(learningOptions: options, cards: cards, progress: progress, contentModified: date)
        #expect(deck.cards == cards)
        #expect(deck.learningOptions == options)
        #expect(deck.progress == progress)
        #expect(deck.contentModified == date)
    }

    @Test func duplicateCardIDsAreRejected() {
        let dom = Card(question: "dom", answer: "Haus")
        let duplicate = Card(id: dom.id, question: "kot", answer: "Katze")
        #expect(throws: Deck.Error.duplicateCardID(duplicate)) {
            try Deck(cards: [dom, Card(question: "pies", answer: "Hund"), duplicate])
        }
    }

    /// The same rules as for options set on a deck, `DeckChange.changingLearningOptions`.
    @Test func learningOptionsAreClampedLikeThoseSetOnADeck() throws {
        var options = LearningOptions()
        options.targetRecall = .nan
        options.maximumInterval = 10
        options.steps = 0
        options.cardsPerSession = 0
        options.newCardsPerSession = 100_000

        let built = try Deck(learningOptions: options, cards: [])
        #expect(built.learningOptions.targetRecall == LearningOptions().targetRecall)
        #expect(built.learningOptions.maximumInterval == LearningOptions.maximumIntervalRange.lowerBound)
        #expect(built.learningOptions.steps == LearningOptions.stepsRange.lowerBound)
        #expect(built.learningOptions.cardsPerSession == LearningOptions.sessionLimitRange.lowerBound)
        #expect(built.learningOptions.newCardsPerSession == LearningOptions.sessionLimitRange.upperBound)

        var changed = Deck()
        _ = changed.apply(try #require(DeckChange.changingLearningOptions(options, in: changed, calendar: .testing)), day: 100)
        #expect(built.learningOptions == changed.learningOptions)
    }
}
