import Foundation
import Testing

@testable import VocabCore

/// Merging two versions of a deck, as Mac and iPhone save them to iCloud Drive.
struct DeckMergeTests {
    let calendar = StudyCalendar.testing
    /// 2026-10-05 18:00 in Berlin.
    let start = Date(timeIntervalSince1970: 1_791_216_000)
    let dom = Card(question: "dom", answer: "Haus")
    let kot = Card(question: "kot", answer: "Katze")
    let pies = Card(question: "pies", answer: "Hund")

    func day(_ days: Double) -> Date {
        start.addingTimeInterval(days * 86400)
    }

    /// The deck both devices start from: "dom" in the review phase, "kot" new and
    /// "pies" reviewed once.
    func baseDeck(fuzzing: Bool = true) throws -> Deck {
        var options = LearningOptions()
        options.fuzzing = fuzzing
        var deck = Deck(learningOptions: options)
        _ = deck.apply(try #require(DeckChange.adding([dom, kot, pies], to: deck)), at: start, calendar: calendar)
        review(&deck, dom.id, .good, at: start.addingTimeInterval(60))
        review(&deck, dom.id, .good, at: start.addingTimeInterval(120))
        review(&deck, pies.id, .hard, at: start.addingTimeInterval(180))
        return deck
    }

    /// Reviews a card like a study session does.
    func review(_ deck: inout Deck, _ id: Card.ID, _ grade: Grade, at date: Date, mode: ReviewMode = .typed) {
        let card = deck.card(withID: id)!
        var random = SeededRandom(seed: 1)
        let reviewed = Scheduler(learningOptions: deck.learningOptions, calendar: calendar).review(card, grade: grade, at: date, mode: mode, using: &random)
        _ = deck.apply(DeckChange(upserts: [reviewed], contentStamp: .keep), at: date, calendar: calendar)
    }

    func merging(_ other: Deck, into deck: Deck, at now: Date) -> Deck {
        var deck = deck
        if let change = DeckChange.merging(other, into: deck, calendar: calendar) {
            _ = deck.apply(change, at: now, calendar: calendar)
        }
        return deck
    }

    @Test func reviewsOfOneVersionAreTakenAsTheyAre() throws {
        let mac = try baseDeck()
        var phone = mac
        review(&phone, dom.id, .good, at: day(3), mode: .revealed)
        review(&phone, kot.id, .again, at: day(3), mode: .revealed)

        let merged = merging(phone, into: mac, at: day(4))
        #expect(merged.cards == phone.cards)
        #expect(merged.contentModified == mac.contentModified)
        #expect(DeckChange.merging(mac, into: phone, calendar: calendar) == nil)
    }

    @Test func reviewsOfBothVersionsAreReplayedInOrder() throws {
        let mac = try baseDeck(fuzzing: false)
        var macLater = mac
        review(&macLater, dom.id, .again, at: day(3))
        review(&macLater, pies.id, .good, at: day(3))
        var phone = mac
        review(&phone, dom.id, .good, at: day(2), mode: .revealed)
        review(&phone, kot.id, .easy, at: day(2), mode: .revealed)

        // Without fuzzing, studying all reviews in order on one device gives the same.
        var expected = mac
        review(&expected, dom.id, .good, at: day(2), mode: .revealed)
        review(&expected, kot.id, .easy, at: day(2), mode: .revealed)
        review(&expected, dom.id, .again, at: day(3))
        review(&expected, pies.id, .good, at: day(3))

        let merged = merging(phone, into: macLater, at: day(4))
        #expect(merged.cards == expected.cards)
        #expect(merged.cards[0].log.map(\.mode) == [.typed, .typed, .revealed, .typed])
        #expect(merged.cards[0].hasCompleteLog)
        #expect(merging(macLater, into: phone, at: day(4)) == merged)
    }

    @Test func replayedReviewsAreFuzzedAlikeOnEveryDevice() throws {
        let mac = try baseDeck()
        var macLater = mac
        var phone = mac
        // Easy moves the cards far enough into the review phase to be fuzzed.
        review(&macLater, dom.id, .easy, at: day(20))
        review(&phone, dom.id, .easy, at: day(15), mode: .revealed)

        let merged = merging(phone, into: macLater, at: day(21))
        #expect(merging(macLater, into: phone, at: day(21)) == merged)
        let replayed = try #require(merged.card(withID: dom.id))
        #expect(replayed.learningState?.reviews == 4)
        #expect(replayed.learningState?.lastReview == day(20))
    }

    @Test func contentComesFromTheVersionChangedLast() throws {
        let mac = try baseDeck()
        var phone = mac
        review(&phone, dom.id, .good, at: day(2), mode: .revealed)
        review(&phone, pies.id, .good, at: day(2), mode: .revealed)

        var macLater = mac
        let edit = try #require(DeckChange.editingText(of: dom.id, to: CardText(question: "dom", answer: "Haus / Heim")!, in: macLater))
        _ = macLater.apply(edit, at: day(3), calendar: calendar)
        _ = macLater.apply(try #require(DeckChange.removing([pies.id], from: macLater)), at: day(3), calendar: calendar)
        let added = Card(question: "mysz", answer: "Maus")
        _ = macLater.apply(try #require(DeckChange.adding([added], to: macLater)), at: day(3), calendar: calendar)
        var options = macLater.learningOptions
        options.steps = 3
        _ = macLater.apply(try #require(DeckChange.changingLearningOptions(options, in: macLater, calendar: calendar)), at: day(3), calendar: calendar)

        let merged = merging(macLater, into: phone, at: day(4))
        #expect(merged.cards.map(\.answer) == ["Haus / Heim", "Katze", "Maus"])
        #expect(merged.cards[0].log == phone.cards[0].log)
        #expect(merged.learningOptions.steps == 3)
        #expect(merged.contentModified == day(3))
        #expect(merging(phone, into: macLater, at: day(4)) == merged)
    }

    @Test func aReviewInBothVersionsCountsOnce() throws {
        var mac = try baseDeck()
        // Not on a whole second; the saved version keeps whole seconds only.
        review(&mac, dom.id, .hard, at: day(2).addingTimeInterval(0.75))
        var phone = try DeckFile.decode(DeckFile.fileWrapper(for: mac))
        review(&phone, dom.id, .good, at: day(3), mode: .revealed)
        var macLater = mac
        review(&macLater, dom.id, .again, at: day(4))

        let merged = merging(phone, into: macLater, at: day(5))
        let card = try #require(merged.card(withID: dom.id))
        #expect(card.log.map(\.grade) == [.good, .good, .hard, .good, .again])
        #expect(card.learningState?.reviews == 5)
        #expect(card.hasCompleteLog)
    }

    @Test func aReviewTwiceInOneVersionStaysTwice() throws {
        let mac = try baseDeck()
        var macLater = mac
        review(&macLater, kot.id, .again, at: day(1))
        review(&macLater, kot.id, .again, at: day(1))
        var phone = mac
        review(&phone, kot.id, .again, at: day(1))
        review(&phone, kot.id, .good, at: day(2))

        let card = try #require(merging(phone, into: macLater, at: day(3)).card(withID: kot.id))
        #expect(card.log.map(\.grade) == [.again, .again, .good])
    }

    @Test func incompleteLogsContinueTheVersionReviewedFirst() throws {
        // Imported from MacVocTrain 1 with five reviews, none of them in the log.
        let imported = Card(
            question: "dom",
            answer: "Haus",
            learningState: LearningState(phase: .review, stability: 10, difficulty: 5, lastReview: start, due: day(10), reviews: 5)
        )
        let mac = Deck(cards: [imported], contentModified: start)
        var macLater = mac
        review(&macLater, imported.id, .good, at: day(10))
        review(&macLater, imported.id, .hard, at: day(30))
        var phone = mac
        review(&phone, imported.id, .good, at: day(20), mode: .revealed)

        let merged = merging(phone, into: macLater, at: day(31))
        let card = try #require(merged.card(withID: imported.id))
        // The phone continues with the reviews the Mac added after its own; the one
        // before only joins the log.
        var expected = phone
        review(&expected, imported.id, .hard, at: day(30))
        #expect(card.log.map(\.date) == [day(10), day(20), day(30)])
        #expect(card.learningState?.reviews == 8)
        #expect(card.learningState?.stability == expected.cards[0].learningState?.stability)
        #expect(card.learningState?.lastReview == day(30))
        #expect(!card.hasCompleteLog)
        #expect(merging(macLater, into: phone, at: day(31)) == merged)
    }

    @Test func newParametersOfTheContentReplayTheMemory() throws {
        let mac = try baseDeck()
        var phone = mac
        review(&phone, dom.id, .good, at: day(3), mode: .revealed)

        var macLater = mac
        var options = macLater.learningOptions
        options.parameters = SyntheticLearner.unusual
        _ = macLater.apply(try #require(DeckChange.changingLearningOptions(options, in: macLater, calendar: calendar)), at: day(2), calendar: calendar)

        let merged = merging(phone, into: macLater, at: day(4))
        let card = try #require(merged.card(withID: dom.id))
        let scheduler = Scheduler(learningOptions: options, calendar: calendar)
        #expect(card == scheduler.replayingMemory(of: phone.cards[0]))
        #expect(card.learningState?.due == phone.cards[0].learningState?.due)
    }

    @Test func progressJoinsTheDaysOfBothVersions() throws {
        let mac = try baseDeck()
        var macLater = mac
        review(&macLater, pies.id, .good, at: day(1))
        var phone = mac
        review(&phone, kot.id, .good, at: day(2), mode: .revealed)
        review(&phone, kot.id, .good, at: day(3), mode: .revealed)

        let merged = merging(phone, into: macLater, at: day(4))
        let today = calendar.dayNumber(for: day(4))
        #expect(merged.progress.map(\.day) == [today - 4, today - 3, today - 2, today - 1, today])
        #expect(merged.progress.last?.bins == StabilityBins.histogram(of: merged.cards))
        // The day the Mac studied, then the ones the phone studied.
        #expect(merged.progress[1] == macLater.progress[1])
        #expect(Array(merged.progress[2...3]) == Array(phone.progress[1...2]))
    }

    @Test func undoingAMergeRestoresTheVersion() throws {
        let mac = try baseDeck()
        var phone = mac
        review(&phone, dom.id, .good, at: day(3), mode: .revealed)
        var macLater = mac
        _ = macLater.apply(try #require(DeckChange.removing([kot.id], from: macLater)), at: day(2), calendar: calendar)

        var merged = phone
        let change = try #require(DeckChange.merging(macLater, into: merged, calendar: calendar))
        let inverse = merged.apply(change, at: day(4), calendar: calendar)
        #expect(merged.cards.map(\.question) == ["dom", "pies"])
        _ = merged.apply(inverse, at: day(4), calendar: calendar)
        #expect(merged.cards == phone.cards)
        #expect(merged.contentModified == phone.contentModified)
        #expect(merged.learningOptions == phone.learningOptions)
    }

    @Test func mergingTheSameVersionChangesNothing() throws {
        let deck = try baseDeck()
        #expect(DeckChange.merging(deck, into: deck, calendar: calendar) == nil)
        #expect(DeckChange.merging(try DeckFile.decode(DeckFile.fileWrapper(for: deck)), into: deck, calendar: calendar) == nil)
    }
}
