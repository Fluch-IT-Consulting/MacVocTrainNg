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

struct StudySessionTests {
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    func deck(newCards: Int, reviewCards: Int = 0) -> Deck {
        var cards = (0..<newCards).map { Card(question: "q\($0)", answer: "a\($0)") }
        for index in 0..<reviewCards {
            var card = Card(question: "r\(index)", answer: "b\(index)")
            card.memory = MemoryState(
                phase: .review,
                stability: 5,
                difficulty: 5,
                lastReview: now.addingTimeInterval(-Double(5 + index) * 86400),
                due: now.addingTimeInterval(-86400)
            )
            cards.append(card)
        }
        var settings = DeckSettings()
        settings.fuzzing = false
        settings.cardsPerSession = nil
        return Deck(settings: settings, cards: cards)
    }

    /// Plays a session to the end, answering every card with `answer`.
    func play(_ session: inout StudySession, deck: inout Deck, answer: (Card) -> Grade) -> Int {
        let scheduler = Scheduler(settings: deck.settings)
        var steps = 0
        while let id = session.currentCardID, steps < 10_000 {
            let index = deck.index(of: id)!
            let grade = answer(deck.cards[index])
            deck.cards[index] = scheduler.review(deck.cards[index], grade: grade, at: now)
            session.record(grade, scheduledCard: deck.cards[index])
            steps += 1
        }
        return steps
    }

    @Test func newCardsNeedLearningStepsCorrectAnswers() {
        var deck = deck(newCards: 12)
        var session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 1))
        #expect(session.totalCount == 12)
        let answers = play(&session, deck: &deck) { _ in .good }
        #expect(answers == 12 * deck.settings.learningSteps)
        #expect(session.isFinished)
        #expect(session.completedCount == 12)
        #expect(deck.cards.allSatisfy { $0.memory?.phase == .review })
    }

    @Test func reviewCardsNeedOneCorrectAnswer() {
        var deck = deck(newCards: 0, reviewCards: 8)
        var session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 1))
        let answers = play(&session, deck: &deck) { _ in .good }
        #expect(answers == 8)
        #expect(session.failedCardIDs.isEmpty)
    }

    @Test func failedCardsComeBackUntilRelearned() {
        var deck = deck(newCards: 0, reviewCards: 5)
        let failing = deck.cards[0].id
        var session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 2))
        var failedOnce = false
        let answers = play(&session, deck: &deck) { card in
            if card.id == failing, !failedOnce {
                failedOnce = true
                return .again
            }
            return .good
        }
        // 1 failure + learningSteps answers to relearn + 4 other cards.
        #expect(answers == 1 + deck.settings.learningSteps + 4)
        #expect(session.failedCardIDs == [failing])
        #expect(session.correctCount == answers - 1)
        #expect(deck.card(withID: failing)?.memory?.lapses == 1)
    }

    @Test func onlyDueCardsAreSelected() {
        var deck = deck(newCards: 2, reviewCards: 2)
        deck.cards[3].memory?.due = now.addingTimeInterval(86400)
        let session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 4))
        #expect(session.totalCount == 3)
    }

    @Test func newCardLimitIsRespected() {
        var deck = deck(newCards: 10, reviewCards: 3)
        deck.settings.newCardsPerSession = 4
        let session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 4))
        #expect(session.totalCount == 7)
    }

    @Test func sessionSizeIsLimited() {
        var deck = deck(newCards: 10, reviewCards: 10)
        deck.settings.cardsPerSession = 5
        #expect(StudySession(deck: deck, at: now, random: SeededRandom(seed: 4)).totalCount == 5)
        deck.settings.cardsPerSession = nil
        #expect(StudySession(deck: deck, at: now, random: SeededRandom(seed: 4)).totalCount == 20)
    }

    @Test func learningCardsAreIntroducedBeforeNewAndReviewCards() {
        var deck = deck(newCards: 30, reviewCards: 30)
        var relearning = Card(question: "x", answer: "y")
        relearning.memory = MemoryState(phase: .relearning, stability: 1, difficulty: 5, lastReview: now, due: now)
        deck.cards.append(relearning)
        var random = SeededRandom(seed: 8)
        let order = StudySession.selectCards(from: deck, at: now, using: &random)
        #expect(order.first == relearning.id)
        let newIDs = Set(deck.cards.filter(\.isNew).map(\.id))
        #expect(order.dropFirst().prefix(30).allSatisfy(newIDs.contains))
    }

    @Test func finishUpEndsAfterStartedCards() {
        var deck = deck(newCards: 40)
        var session = StudySession(deck: deck, at: now, random: SeededRandom(seed: 6))
        let scheduler = Scheduler(settings: deck.settings)
        for _ in 0..<3 {
            let index = deck.index(of: session.currentCardID!)!
            deck.cards[index] = scheduler.review(deck.cards[index], grade: .good, at: now)
            session.record(.good, scheduledCard: deck.cards[index])
        }
        let started = session.startedCount
        let completed = session.completedCount
        #expect(started > 0)
        session.finishUp()
        #expect(session.remainingCount == started)
        #expect(session.completedCount == completed)
        #expect(session.totalCount == completed + started)
        _ = play(&session, deck: &deck) { _ in .good }
        #expect(session.isFinished)
    }

    @Test func practiceRequiresStreakAfterFailure() {
        let ids = [UUID(), UUID()]
        var session = StudySession(practicing: ids, learningSteps: 2, at: now, random: SeededRandom(seed: 1))
        let target = session.currentCardID!
        session.record(.again)
        var answers = 1
        while !session.isFinished {
            session.record(.good)
            answers += 1
        }
        // target needs 2 correct answers after failing, the other card one.
        #expect(answers == 1 + 2 + 1)
        #expect(session.failedCardIDs == [target])
    }

    @Test func skipDropsCardWithoutCountingIt() {
        var session = StudySession(deck: deck(newCards: 2), at: now, random: SeededRandom(seed: 1))
        let skipped = session.currentCardID
        session.skip()
        #expect(session.totalCount == 1)
        #expect(session.answerCount == 0)
        #expect(session.currentCardID != skipped)
        session.skip()
        #expect(session.isFinished)
    }

    @Test func stopEndsImmediately() {
        var session = StudySession(deck: deck(newCards: 3), at: now, random: SeededRandom(seed: 1))
        session.stop()
        #expect(session.isFinished)
    }
}
