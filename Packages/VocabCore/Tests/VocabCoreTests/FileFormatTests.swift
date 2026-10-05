import Foundation
import Testing
@testable import VocabCore

struct DeckFileTests {
    let date = Date(timeIntervalSince1970: 1_791_216_000)

    @Test func roundTripPreservesEverything() throws {
        var settings = DeckSettings()
        settings.desiredRetention = 0.85
        settings.newCardsPerSession = 15
        settings.cardsPerSession = nil
        var card = Card(question: "dom", answer: "Haus / Gebäude", remark: "Substantiv", created: date)
        card.memory = MemoryState(phase: .review, step: 0, stability: 12.5, difficulty: 4.2, lastReview: date, due: date.addingTimeInterval(86400), reps: 3, lapses: 1)
        card.log = [ReviewLogEntry(date: date, grade: .hard)]
        let deck = Deck(settings: settings, cards: [card, Card(question: "kot", answer: "Katze", created: date)], history: [DailySnapshot(day: 20_000, bins: [1, 1])])

        let decoded = try DeckFile.decode(DeckFile.encode(deck))
        #expect(decoded == deck)
    }

    @Test func fileIsReadableJSON() throws {
        let data = try DeckFile.encode(Deck(cards: [Card(question: "dom", answer: "Haus", created: date)]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"format\" : \"com.mfluch.voctrain.deck\""))
        #expect(text.contains("\"question\" : \"dom\""))
        #expect(!text.contains("\"remark\""))
        #expect(!text.contains("\"log\""))
    }

    @Test func optionalFieldsMayBeMissing() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 1, "settings": {},
         "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus"}],
         "history": []}
        """
        let deck = try DeckFile.decode(Data(json.utf8))
        #expect(deck.cards.first?.remark == "")
        #expect(deck.cards.first?.memory == nil)
        #expect(deck.settings == DeckSettings())
    }

    @Test func rejectsForeignAndFutureFiles() {
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(Data("{\"foo\": 1}".utf8)) }
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(Data("not json".utf8)) }
        let future = Data("{\"format\": \"com.mfluch.voctrain.deck\", \"version\": 99}".utf8)
        #expect(throws: DeckFile.Error.unsupportedVersion(99)) { try DeckFile.decode(future) }
    }
}

struct LegacyImporterTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)
    let now = Date(timeIntervalSince1970: 1_791_216_000)

    /// Builds an archive exactly like MacVocTrain 1 wrote it.
    func legacyArchive(cards: [LegacyIndexCard], progress: [LegacyDailyStatus]) throws -> Data {
        let box = LegacyBox()
        box.indexCards = cards
        let monitor = LegacyProgressMonitor()
        monitor.progressData = progress
        box.progressMonitor = monitor

        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("IndexCardBoxHelper", for: LegacyBox.self)
        archiver.setClassName("IndexCard", for: LegacyIndexCard.self)
        archiver.setClassName("ProgressMonitor", for: LegacyProgressMonitor.self)
        archiver.setClassName("DailyStatus", for: LegacyDailyStatus.self)
        archiver.setClassName("Counter", for: LegacyCounter.self)
        archiver.encode(box, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    func legacyCard(_ question: String, level: Int, lastAnswered: Date?, adjustment: Float = 0) -> LegacyIndexCard {
        let card = LegacyIndexCard()
        card.question = question
        card.answer = "answer of \(question)"
        card.remarkQuestion = level == 3 ? "hint" : nil
        card.level = level
        card.lastAnswered = lastAnswered
        card.levelDurationAdjustment = adjustment
        return card
    }

    @Test func levelDurationsMatchMacVocTrain1() {
        #expect(LegacyImporter.levelDuration(1) == 0.7)
        #expect(LegacyImporter.levelDuration(12) == 22)
        #expect(abs(LegacyImporter.levelDuration(14) - 29.04) < 1e-9)
    }

    @Test func importsCardsAndConvertsLevels() throws {
        let lastAnswered = now.addingTimeInterval(-86400)
        let data = try legacyArchive(
            cards: [
                legacyCard("new", level: 0, lastAnswered: nil),
                legacyCard("failed", level: 0, lastAnswered: lastAnswered),
                legacyCard("known", level: 3, lastAnswered: lastAnswered, adjustment: 0.1),
            ],
            progress: []
        )
        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.cards.map(\.question) == ["new", "failed", "known"])
        #expect(deck.cards[0].isNew)

        let failed = try #require(deck.cards[1].memory)
        #expect(failed.phase == .relearning)
        #expect(deck.cards[1].isDue(at: now))

        let known = try #require(deck.cards[2].memory)
        #expect(known.phase == .review)
        #expect(abs(known.stability - 1.8 * 1.1) < 1e-6)
        #expect(abs(known.due.timeIntervalSince(lastAnswered) - 1.8 * 1.1 * 86400) < 1)
        #expect(deck.cards[2].remark == "hint")
        #expect(deck.cards[2].answer == "answer of known")
    }

    @Test func importsProgressHistory() throws {
        let status = LegacyDailyStatus()
        status.date = 20_141_108
        status.counters = [LegacyCounter(value: 5), LegacyCounter(value: 2), LegacyCounter(value: 0), LegacyCounter(value: 1)]
        let data = try legacyArchive(cards: [legacyCard("x", level: 0, lastAnswered: nil)], progress: [status])

        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.history.count == 2)
        let first = deck.history[0]
        #expect(CivilDate(dayNumber: first.day).isoString == "2014-11-08")
        #expect(first.bins[1] == 7)  // level 0 and level 1 (0.7 days)
        #expect(first.bins[2] == 1)  // level 3 (1.8 days)
        #expect(deck.history[1].day == calendar.dayNumber(for: now))
    }

    @Test func rejectsGarbage() {
        #expect(throws: LegacyImporter.Error.unreadableArchive) {
            try LegacyImporter.importDeck(from: Data("nope".utf8))
        }
    }

    /// Set MVT_SAMPLE to the path of a real MacVocTrain 1 document to check it imports.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MVT_SAMPLE"] != nil))
    func importsRealDocument() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MVT_SAMPLE"]!)
        let deck = try LegacyImporter.importDeck(from: Data(contentsOf: url))
        print("Imported \(deck.cards.count) cards, \(deck.history.count) history entries")
        print("New: \(deck.cards.filter(\.isNew).count), due now: \(deck.cards.filter { $0.isDue(at: Date()) }.count)")
        #expect(!deck.cards.isEmpty)
        #expect(deck.cards.allSatisfy { !$0.question.isEmpty })
    }
}
