import Foundation
import Testing
@testable import VocabCore

struct DeckChangeTests {
    private let start = Date(timeIntervalSince1970: 1_791_216_000)

    /// A card reviewed three times, so its log reaches back to its first review.
    private func studiedCard() -> Card {
        let scheduler = Scheduler(learningOptions: LearningOptions(), calendar: .testing)
        var random = SeededRandom(seed: 1)
        return [(0.0, Grade.good), (60.0, .good), (20.0 * 86400, .good)].reduce(Card(question: "dom", answer: "Haus")) {
            scheduler.review($0, grade: $1.1, at: start.addingTimeInterval($1.0), using: &random)
        }
    }

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

    @Test func addingAppendsNewCards() throws {
        let existing = Card(question: "dom", answer: "Haus")
        var deck = Deck(cards: [existing])
        let added = [Card(question: "kot", answer: "Katze"), Card(question: "pies", answer: "Hund")]

        _ = deck.apply(try #require(DeckChange.adding(added, to: deck)), day: 100)
        #expect(deck.cards == [existing] + added)
    }

    @Test func addingNeverReplacesACard() {
        let studied = studiedCard()
        let deck = Deck(cards: [studied])
        var renamed = studied
        renamed.answer = "Heim"
        let reset = Card(id: studied.id, question: "dom", answer: "Haus")

        #expect(DeckChange.adding([renamed], to: deck) == nil)
        #expect(DeckChange.adding([reset], to: deck) == nil)
    }

    @Test func addingSkipsCardsWithALearningStateOrALog() throws {
        let new = Card(question: "kot", answer: "Katze")
        let studied = studiedCard()
        let logOnly = Card(question: "pies", answer: "Hund", log: studied.log)
        var deck = Deck()

        _ = deck.apply(try #require(DeckChange.adding([studied, new, logOnly], to: deck)), day: 100)
        #expect(deck.cards == [new])
    }

    @Test func addingACardTwiceAddsItOnce() throws {
        let card = Card(question: "dom", answer: "Haus")
        var deck = Deck()

        _ = deck.apply(try #require(DeckChange.adding([card, card], to: deck)), day: 100)
        #expect(deck.cards == [card])
    }

    @Test func removingOnlyRemovesCardsOfTheDeck() throws {
        let cards = [Card(question: "dom", answer: "Haus"), Card(question: "kot", answer: "Katze")]
        var deck = Deck(cards: cards)

        #expect(DeckChange.removing([UUID()], from: deck) == nil)
        _ = deck.apply(try #require(DeckChange.removing([cards[0].id, UUID()], from: deck)), day: 100)
        #expect(deck.cards == [cards[1]])
    }

    @Test func editingTextKeepsTheLearningState() throws {
        let studied = studiedCard()
        var deck = Deck(cards: [Card(question: "kot", answer: "Katze"), studied])

        let change = try #require(DeckChange.editingText(of: studied.id, to: CardText(question: "dom", answer: "Haus / Heim", hint: "Gebäude")!, in: deck))
        _ = deck.apply(change, day: 100)
        let edited = try #require(deck.card(withID: studied.id))
        #expect((edited.question, edited.answer, edited.hint) == ("dom", "Haus / Heim", "Gebäude"))
        #expect(edited.learningState == studied.learningState)
        #expect(edited.log == studied.log)
        #expect(edited.created == studied.created)
    }

    @Test func editingTheSameTextOrAMissingCardChangesNothing() {
        let card = Card(question: "dom", answer: "Haus")
        let deck = Deck(cards: [card])
        #expect(DeckChange.editingText(of: card.id, to: CardText(question: "dom ", answer: "Haus")!, in: deck) == nil)
        #expect(DeckChange.editingText(of: UUID(), to: CardText(question: "kot", answer: "Katze")!, in: deck) == nil)
    }

    @Test func resettingTakesOnlySelectedCardsThatWereStudied() throws {
        let studied = Card(question: "dom", answer: "Haus", learningState: LearningState(phase: .review, stability: 5, difficulty: 5, lastReview: start, due: start))
        let new = Card(question: "kot", answer: "Katze")
        let other = Card(question: "pies", answer: "Hund", learningState: studied.learningState)
        var deck = Deck(cards: [studied, new, other])

        let change = try #require(DeckChange.resettingLearningState(of: [studied.id, new.id], in: deck))
        _ = deck.apply(change, day: 100)
        #expect(deck.cards[0] == Card(id: studied.id, question: "dom", answer: "Haus"))
        #expect(deck.cards[1] == new)
        #expect(deck.cards[2] == other)
    }

    @Test func resettingNewCardsChangesNothing() {
        let deck = Deck(cards: [Card(question: "dom", answer: "Haus")])
        #expect(DeckChange.resettingLearningState(of: [deck.cards[0].id], in: deck) == nil)
        #expect(DeckChange.resettingLearningState(of: [UUID()], in: deck) == nil)
    }

    @Test func unchangedLearningOptionsChangeNothing() {
        let deck = Deck(cards: [Card(question: "dom", answer: "Haus")])
        #expect(DeckChange.changingLearningOptions(LearningOptions(), in: deck, calendar: .testing) == nil)
    }

    @Test func learningOptionsAreClampedToTheirRanges() throws {
        var deck = Deck()
        var options = LearningOptions()
        options.steps = 0
        options.targetRecall = 2

        _ = deck.apply(try #require(DeckChange.changingLearningOptions(options, in: deck, calendar: .testing)), day: 100)
        #expect(deck.learningOptions.steps == 1)
        #expect(deck.learningOptions.targetRecall == 0.97)
    }

    @Test func learningOptionsThatClampToTheCurrentOnesChangeNothing() {
        var options = LearningOptions()
        options.steps = 5
        let deck = Deck(learningOptions: options)
        options.steps = 6
        #expect(DeckChange.changingLearningOptions(options, in: deck, calendar: .testing) == nil)
    }

    @Test func learningOptionsWithoutNewParametersLeaveTheCards() throws {
        let studied = studiedCard()
        var deck = Deck(cards: [studied])
        var options = LearningOptions()
        options.steps = 3

        let change = try #require(DeckChange.changingLearningOptions(options, in: deck, calendar: .testing))
        _ = deck.apply(change, day: 100)
        #expect(deck.learningOptions == options)
        #expect(deck.cards == [studied])
        #expect(deck.progress.isEmpty)
    }

    @Test func newParametersReplayMemoryOfCardsWithCompleteLog() throws {
        let studied = studiedCard()
        let imported = Card(
            question: "kot",
            answer: "Katze",
            learningState: LearningState(phase: .review, stability: 12, difficulty: 5, lastReview: start, due: start, reviews: 3)
        )
        var deck = Deck(cards: [studied, imported])

        var options = LearningOptions()
        var weights = FSRSParameters.default.weights
        weights[8] = 1.2
        options.parameters = try #require(FSRSParameters(weights))
        let change = try #require(DeckChange.changingLearningOptions(options, in: deck, calendar: .testing))
        _ = deck.apply(change, day: 100)

        let replayed = try #require(deck.cards[0].learningState)
        #expect(replayed.stability < studied.learningState!.stability)
        #expect(replayed.due == studied.learningState!.due)
        #expect(deck.cards[0].log == studied.log)
        #expect(deck.cards[1] == imported)
        #expect(deck.learningOptions.parameters == options.parameters)
    }

    @Test func dueCardsAreCountedAtTheGivenTime() {
        let due = start.addingTimeInterval(3600)
        let scheduled = Card(question: "dom", answer: "Haus", learningState: LearningState(phase: .review, stability: 1, difficulty: 5, lastReview: start, due: due))
        let deck = Deck(cards: [scheduled, Card(question: "kot", answer: "Katze")])
        #expect(deck.dueCount(at: start) == 1)
        #expect(deck.dueCount(at: due) == 2)
    }

    @Test func recallProbabilityFollowsTheLearningOptions() throws {
        let calendar = StudyCalendar.testing
        let learningState = LearningState(phase: .review, stability: 10, difficulty: 5, lastReview: start, due: start)
        let card = Card(question: "dom", answer: "Haus", learningState: learningState)
        // After as many days as the stability, every decay gives 90 %; later they differ.
        let later = start.addingTimeInterval(20 * 86400)
        var options = LearningOptions()
        options.parameters = try #require(FSRSParameters(FSRSParameters.default.weights.enumerated().map { $0 == 20 ? $1 * 2 : $1 }))

        let standard = try #require(Deck(cards: [card]).recallProbability(of: card, at: later, calendar: calendar))
        let custom = try #require(Deck(learningOptions: options, cards: [card]).recallProbability(of: card, at: later, calendar: calendar))
        #expect(standard < 0.9)
        #expect(custom == Scheduler(learningOptions: options, calendar: calendar).recallProbability(of: learningState, at: later))
        #expect(custom != standard)
        #expect(Deck().recallProbability(of: Card(question: "kot", answer: "Katze"), at: later, calendar: calendar) == nil)
    }

    @Test func cardsAreFoundByTheirQuestion() {
        let deck = Deck(cards: [Card(question: "dom", answer: "Haus"), Card(question: "kot", answer: "Katze")])
        #expect(deck.cards(withQuestion: "dom").map(\.answer) == ["Haus"])
        #expect(deck.cards(withQuestion: "pies").isEmpty)
        #expect(deck.cards(withQuestion: "").isEmpty)
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
