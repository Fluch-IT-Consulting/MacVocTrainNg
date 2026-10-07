import Foundation
import Testing

@testable import VocabCore

struct SessionQueueTests {
    @Test func neverAsksTheSameCardTwiceInARow() {
        let ids = (0..<30).map { _ in UUID() }
        var queue = SessionQueue(cardIDs: ids)
        var random = SeededRandom(seed: 3)
        var previous: UUID?
        for _ in 0..<200 {
            let id = queue.next(using: &random)!
            #expect(id != previous)
            previous = id
        }
    }

    @Test func singleRemainingCardIsRepeated() {
        let id = UUID()
        var queue = SessionQueue(cardIDs: [id])
        var random = SeededRandom(seed: 3)
        #expect(queue.next(using: &random) == id)
        #expect(queue.next(using: &random) == id)
        queue.remove(id)
        #expect(queue.next(using: &random) == nil)
        #expect(queue.isEmpty)
    }

    @Test func finishUpKeepsOnlyCardsAlreadyAsked() {
        let ids = (0..<40).map { _ in UUID() }
        var queue = SessionQueue(cardIDs: ids)
        var random = SeededRandom(seed: 9)
        let asked = Set((0..<3).compactMap { _ in queue.next(using: &random) })
        queue.finishUp()
        #expect(queue.count == asked.count)
        #expect(queue.startedCount == asked.count)
    }

    @Test func urgentCardsComeFirst() {
        let ids = (0..<100).map { _ in UUID() }
        var queue = SessionQueue(cardIDs: ids)
        var random = SeededRandom(seed: 5)
        var firstTen: [UUID] = []
        while firstTen.count < 10 {
            let id = queue.next(using: &random)!
            queue.remove(id)
            firstTen.append(id)
        }
        // Only cards of the first block of 25 can show up early.
        #expect(firstTen.allSatisfy { ids.prefix(SessionQueue.stagingSize).contains($0) })
    }
}

struct SessionTests {
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    func deck(newCards: Int, reviewCards: Int = 0) -> Deck {
        var cards = (0..<newCards).map { Card(question: "q\($0)", answer: "a\($0)") }
        for index in 0..<reviewCards {
            var card = Card(question: "r\(index)", answer: "b\(index)")
            card.learningState = LearningState(
                phase: .review,
                stability: 5,
                difficulty: 5,
                lastReview: now.addingTimeInterval(-Double(5 + index) * 86400),
                due: now.addingTimeInterval(-86400)
            )
            cards.append(card)
        }
        var learningOptions = LearningOptions()
        learningOptions.fuzzing = false
        learningOptions.cardsPerSession = nil
        return Deck(learningOptions: learningOptions, cards: cards)
    }

    /// Plays a session to the end, grading every card with `grading`.
    func play(_ study: inout StudySession, deck: inout Deck, grading: (Card) -> Grade) -> Int {
        var steps = 0
        while let id = study.session.currentCardID, steps < 10_000 {
            review(&study, deck: &deck, grading(deck.card(withID: id)!))
            steps += 1
        }
        return steps
    }

    /// Reviews the current card and stores it in `deck`, like the app does.
    func review(_ study: inout StudySession, deck: inout Deck, _ grade: Grade) {
        let card = study.review(grade, in: deck, at: now)!
        deck.cards[deck.index(of: card.id)!] = card
    }

    @Test func newCardsNeedAllSteps() {
        var deck = deck(newCards: 12)
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        #expect(study.session.totalCount == 12)
        let reviews = play(&study, deck: &deck) { _ in .good }
        #expect(reviews == 12 * deck.learningOptions.steps)
        #expect(study.session.isFinished)
        #expect(study.session.completedCount == 12)
        #expect(deck.cards.allSatisfy { $0.learningState?.phase == .review })
    }

    @Test func cardsInReviewPhaseNeedOneRecall() {
        var deck = deck(newCards: 0, reviewCards: 8)
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        let reviews = play(&study, deck: &deck) { _ in .good }
        #expect(reviews == 8)
        #expect(study.session.mistakeIDs.isEmpty)
    }

    @Test func mistakesComeBackUntilRelearned() {
        var deck = deck(newCards: 0, reviewCards: 5)
        let mistake = deck.cards[0].id
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 2))
        var gotAgain = false
        let reviews = play(&study, deck: &deck) { card in
            if card.id == mistake, !gotAgain {
                gotAgain = true
                return .again
            }
            return .good
        }
        // 1 again + all steps to relearn + 4 other cards.
        #expect(reviews == 1 + deck.learningOptions.steps + 4)
        #expect(study.session.mistakeIDs == [mistake])
        #expect(study.session.recalledCount == reviews - 1)
        #expect(deck.card(withID: mistake)?.learningState?.lapses == 1)
    }

    @Test func reviewReturnsTheCurrentCardScheduled() {
        let deck = deck(newCards: 3)
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        let id = study.session.currentCardID!
        let card = study.review(.good, in: deck, at: now)!
        var random = SeededRandom(seed: 1)
        let expected = Scheduler(learningOptions: deck.learningOptions, calendar: .testing).review(deck.card(withID: id)!, grade: .good, at: now, using: &random)
        #expect(card == expected)
        #expect(study.session.reviewCount == 1)
    }

    @Test func sameSeedGivesSameDueDatesWithFuzzing() {
        var deck = deck(newCards: 0, reviewCards: 20)
        deck.learningOptions.fuzzing = true
        func dueDates(seed: UInt64) -> [Card.ID: Date] {
            var deck = deck
            var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: seed))
            _ = play(&study, deck: &deck) { _ in .good }
            return Dictionary(uniqueKeysWithValues: deck.cards.map { ($0.id, $0.learningState!.due) })
        }
        #expect(dueDates(seed: 3) == dueDates(seed: 3))
        // The fuzz is real: another seed spreads the intervals differently.
        #expect(dueDates(seed: 3) != dueDates(seed: 4))
    }

    @Test func fuzzingDoesNotChangeTheOrder() {
        let reviewDeck = deck(newCards: 0, reviewCards: 20)
        func order(fuzzing: Bool) -> [Card.ID] {
            var deck = reviewDeck
            deck.learningOptions.fuzzing = fuzzing
            var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 3))
            var asked: [Card.ID] = []
            _ = play(&study, deck: &deck) { card in
                asked.append(card.id)
                return .good
            }
            return asked
        }
        #expect(order(fuzzing: true) == order(fuzzing: false))
    }

    @Test func cardLeavesOnlyInReviewPhase() {
        var deck = deck(newCards: 1)
        deck.learningOptions.steps = 2
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        review(&study, deck: &deck, .good)
        #expect(deck.cards[0].learningState?.phase == .learning)
        #expect(!study.session.isFinished)
        review(&study, deck: &deck, .good)
        #expect(deck.cards[0].learningState?.phase == .review)
        #expect(study.session.isFinished)
    }

    @Test func reviewUsesTheLearningOptionsOfTheDeckPassed() {
        var deck = deck(newCards: 1)
        deck.learningOptions.steps = 3
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        review(&study, deck: &deck, .good)
        deck.learningOptions.steps = 2
        review(&study, deck: &deck, .good)
        #expect(deck.cards[0].learningState?.phase == .review)
        #expect(study.session.isFinished)
    }

    @Test func reviewWithoutCurrentCardChangesNothing() {
        var deck = deck(newCards: 2)
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        deck.cards.removeAll { $0.id == study.session.currentCardID }
        #expect(study.review(.good, in: deck, at: now) == nil)
        #expect(study.session.reviewCount == 0)
        study.perform(.skip)
        study.perform(.skip)
        #expect(study.session.isFinished)
        #expect(study.review(.good, in: deck, at: now) == nil)
    }

    @Test func onlyDueCardsAreSelected() {
        var deck = deck(newCards: 2, reviewCards: 2)
        deck.cards[3].learningState?.due = now.addingTimeInterval(86400)
        let session = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 4)).session
        #expect(session.totalCount == 3)
    }

    @Test func newCardLimitIsRespected() {
        var deck = deck(newCards: 10, reviewCards: 3)
        deck.learningOptions.newCardsPerSession = 4
        let session = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 4)).session
        #expect(session.totalCount == 7)
    }

    @Test func sessionSizeIsLimited() {
        var deck = deck(newCards: 10, reviewCards: 10)
        deck.learningOptions.cardsPerSession = 5
        #expect(StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 4)).session.totalCount == 5)
        deck.learningOptions.cardsPerSession = nil
        #expect(StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 4)).session.totalCount == 20)
    }

    @Test func learningCardsAreIntroducedBeforeNewAndReviewCards() {
        var deck = deck(newCards: 30, reviewCards: 30)
        var relearning = Card(question: "x", answer: "y")
        relearning.learningState = LearningState(phase: .relearning, stability: 1, difficulty: 5, lastReview: now, due: now)
        deck.cards.append(relearning)
        var random = SeededRandom(seed: 8)
        let order = StudySession.selectCards(from: deck, at: now, calendar: .testing, using: &random)
        #expect(order.first == relearning.id)
        let newIDs = Set(deck.cards.filter(\.isNew).map(\.id))
        #expect(order.dropFirst().prefix(30).allSatisfy(newIDs.contains))
    }

    @Test func finishUpEndsAfterStartedCards() {
        var deck = deck(newCards: 40)
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 6))
        for _ in 0..<3 {
            review(&study, deck: &deck, .good)
        }
        let started = study.session.startedCount
        let completed = study.session.completedCount
        #expect(started > 0)
        study.perform(.finishUp)
        #expect(study.session.remainingCount == started)
        #expect(study.session.completedCount == completed)
        #expect(study.session.totalCount == completed + started)
        _ = play(&study, deck: &deck) { _ in .good }
        #expect(study.session.isFinished)
    }

    @Test func practiceRequiresStepsAfterAgain() {
        let ids = [UUID(), UUID()]
        var practice = Practice(practicing: ids, steps: 2, at: now, random: SeededRandom(seed: 1))
        let target = practice.session.currentCardID!
        practice.record(.again)
        var reviews = 1
        while !practice.session.isFinished {
            practice.record(.good)
            reviews += 1
        }
        // target needs 2 steps after its again, the other card one.
        #expect(reviews == 1 + 2 + 1)
        #expect(practice.session.mistakeIDs == [target])
    }

    @Test func practiceHardKeepsStepAfterAgain() {
        var practice = Practice(practicing: [UUID()], steps: 2, at: now, random: SeededRandom(seed: 1))
        practice.record(.again)
        practice.record(.hard)
        practice.record(.hard)
        #expect(!practice.session.isFinished)
        practice.record(.good)
        practice.record(.hard)
        #expect(!practice.session.isFinished)
        practice.record(.good)
        #expect(practice.session.isFinished)
    }

    @Test func practiceAgainResetsSteps() {
        var practice = Practice(practicing: [UUID()], steps: 2, at: now, random: SeededRandom(seed: 1))
        practice.record(.again)
        practice.record(.good)
        practice.record(.again)
        practice.record(.good)
        #expect(!practice.session.isFinished)
        practice.record(.good)
        #expect(practice.session.isFinished)
    }

    @Test func practiceEasyEndsCardAfterAgain() {
        var practice = Practice(practicing: [UUID()], steps: 3, at: now, random: SeededRandom(seed: 1))
        practice.record(.again)
        practice.record(.easy)
        #expect(practice.session.isFinished)
    }

    @Test func practiceEndsCardWithoutAgainAfterAnyRecall() {
        var practice = Practice(practicing: [UUID(), UUID()], steps: 2, at: now, random: SeededRandom(seed: 1))
        practice.record(.hard)
        practice.record(.hard)
        #expect(practice.session.isFinished)
    }

    @Test func skipDropsCardWithoutCountingIt() {
        var study = StudySession(deck: deck(newCards: 2), at: now, calendar: .testing, random: SeededRandom(seed: 1))
        let skipped = study.session.currentCardID
        study.perform(.skip)
        #expect(study.session.totalCount == 1)
        #expect(study.session.reviewCount == 0)
        #expect(study.session.currentCardID != skipped)
        study.perform(.skip)
        #expect(study.session.isFinished)
    }

    @Test func gradingInAStudySessionReschedulesTheCard() throws {
        var deck = deck(newCards: 2)
        var mode = SessionMode.study(StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1)))
        var study = StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1))
        let reviewed = study.review(.good, in: deck, at: now)
        let expected = try #require(reviewed)

        guard case let .rescheduled(change) = mode.grade(.good, in: deck, at: now) else {
            Issue.record("The study session didn't reschedule the card")
            return
        }
        _ = deck.apply(change, day: 100)
        #expect(deck.cards.filter { !$0.isNew } == [expected])
        #expect(mode.session.reviewCount == 1)
    }

    @Test func gradingInPracticeChangesNoCard() {
        let deck = deck(newCards: 2)
        var mode = SessionMode.practice(Practice(practicing: deck.cards.map(\.id), steps: 2, at: now, random: SeededRandom(seed: 1)))

        guard case .practiced = mode.grade(.again, in: deck, at: now) else {
            Issue.record("Practice changed a card")
            return
        }
        #expect(mode.session.reviewCount == 1)
        #expect(mode.session.mistakeIDs.count == 1)
    }

    @Test func gradingACardTheDeckNoLongerHoldsRecordsNothing() {
        var deck = deck(newCards: 2)
        let ids = deck.cards.map(\.id)
        var study = SessionMode.study(StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1)))
        var practice = SessionMode.practice(Practice(practicing: ids, steps: 2, at: now, random: SeededRandom(seed: 1)))
        deck.cards.removeAll { $0.id == study.session.currentCardID || $0.id == practice.session.currentCardID }

        #expect(study.grade(.good, in: deck, at: now) == nil)
        #expect(practice.grade(.good, in: deck, at: now) == nil)
        #expect(study.session.reviewCount == 0)
        #expect(practice.session.reviewCount == 0)
    }

    @Test func gradingAFinishedSessionRecordsNothing() {
        let deck = deck(newCards: 1)
        var mode = SessionMode.study(StudySession(deck: deck, at: now, calendar: .testing, random: SeededRandom(seed: 1)))
        mode.perform(.skip)

        #expect(mode.session.isFinished)
        #expect(mode.grade(.good, in: deck, at: now) == nil)
    }
}
