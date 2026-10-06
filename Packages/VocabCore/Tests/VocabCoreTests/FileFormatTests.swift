import Foundation
import Testing
@testable import VocabCore

struct DeckFileTests {
    let date = Date(timeIntervalSince1970: 1_791_216_000)

    func sampleDeck() -> Deck {
        var learningOptions = LearningOptions()
        learningOptions.targetRecall = 0.85
        learningOptions.newCardsPerSession = 15
        learningOptions.cardsPerSession = nil
        var card = Card(question: "dom", answer: "Haus / Gebäude", hint: "Substantiv", created: date)
        card.learningState = LearningState(phase: .review, step: 0, stability: 12.5, difficulty: 4.2, lastReview: date, due: date.addingTimeInterval(86400), reviews: 3, lapses: 1)
        card.log = [ReviewLogEntry(date: date.addingTimeInterval(-86400), grade: .again), ReviewLogEntry(date: date, grade: .hard)]
        return Deck(learningOptions: learningOptions, cards: [card, Card(question: "kot", answer: "Katze", created: date)], progress: [DailySnapshot(day: 20_000, bins: [1, 1])])
    }

    func file(_ wrapper: FileWrapper, _ name: String) -> String {
        String(decoding: wrapper.fileWrappers![name]!.regularFileContents!, as: UTF8.self)
    }

    @Test func packageRoundTripPreservesEverything() throws {
        let deck = sampleDeck()
        #expect(try DeckFile.decode(DeckFile.fileWrapper(for: deck)) == deck)
    }

    @Test func packageHoldsDeckAndReviewLogSeparately() throws {
        let deck = sampleDeck()
        let wrapper = try DeckFile.fileWrapper(for: deck)
        #expect(wrapper.isDirectory)
        #expect(Set(wrapper.fileWrappers!.keys) == [DeckFile.deckFileName, DeckFile.reviewsFileName])

        let deckJSON = file(wrapper, DeckFile.deckFileName)
        #expect(deckJSON.contains("\"format\" : \"com.mfluch.voctrain.deck\""))
        #expect(deckJSON.contains("\"version\" : 3"))
        #expect(deckJSON.contains("\"question\" : \"dom\""))
        for key in ["learningOptions", "targetRecall", "steps", "learningState", "reviews", "hint", "progress"] {
            #expect(deckJSON.contains("\"\(key)\" :"), "missing key \(key)")
        }
        #expect(!deckJSON.contains("\"log\""))
        #expect(!deckJSON.contains("\"hint\" : \"\""))

        let id = deck.cards[0].id.uuidString
        #expect(file(wrapper, DeckFile.reviewsFileName) == """
        {"card":"\(id)","date":1791129600,"grade":1}
        {"card":"\(id)","date":1791216000,"grade":2}

        """)
    }

    @Test func rejectsVersionsBeforeTheFirstRelease() {
        let version1 = Data("""
        {"format": "com.mfluch.voctrain.deck", "version": 1, "settings": {}, "history": [],
         "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus",
                    "created": "2026-10-05T16:00:00Z", "log": [{"date": "2026-10-05T16:00:00Z", "grade": 3}]}]}
        """.utf8)
        #expect(throws: DeckFile.Error.outdatedVersion(1)) { try DeckFile.decode(FileWrapper(regularFileWithContents: version1)) }

        let version2 = Data("""
        {"format": "com.mfluch.voctrain.deck", "version": 2, "settings": {}, "history": [], "cards": []}
        """.utf8)
        let package = FileWrapper(directoryWithFileWrappers: [DeckFile.deckFileName: FileWrapper(regularFileWithContents: version2)])
        #expect(throws: DeckFile.Error.outdatedVersion(2)) { try DeckFile.decode(package) }
    }

    @Test func singleFileOfCurrentVersionIsNoDeck() throws {
        let deckJSON = try DeckFile.encodeDeck(sampleDeck())
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(FileWrapper(regularFileWithContents: deckJSON)) }
    }

    @Test func packageWithoutReviewLogHasEmptyLogs() throws {
        let deck = sampleDeck()
        let wrapper = try DeckFile.fileWrapper(for: deck)
        wrapper.removeFileWrapper(wrapper.fileWrappers![DeckFile.reviewsFileName]!)
        #expect(try DeckFile.decode(wrapper).cards.allSatisfy(\.log.isEmpty))
    }

    @Test func reviewsOfUnknownCardsAreDropped() throws {
        let deck = sampleDeck()
        let reviews = Data(file(try DeckFile.fileWrapper(for: deck), DeckFile.reviewsFileName).utf8)
        var remaining = [deck.cards[1]] // the card with reviews was deleted
        try ReviewLogEncoder.attach(reviews, to: &remaining)
        #expect(remaining == [deck.cards[1]])
    }

    @Test func damagedReviewLineIsReported() throws {
        let wrapper = try DeckFile.fileWrapper(for: sampleDeck())
        var lines = file(wrapper, DeckFile.reviewsFileName)
        lines += "{\"card\":\"nonsense\"}\n"
        wrapper.removeFileWrapper(wrapper.fileWrappers![DeckFile.reviewsFileName]!)
        wrapper.addRegularFile(withContents: Data(lines.utf8), preferredFilename: DeckFile.reviewsFileName)
        #expect(throws: DeckFile.Error.damagedReviewLog(line: 3)) { try DeckFile.decode(wrapper) }
    }

    @Test func packageWithoutDeckIsRejected() {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(wrapper) }
    }

    @Test func optionalFieldsMayBeMissing() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 3, "learningOptions": {},
         "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus"}],
         "progress": []}
        """
        let deck = try DeckFile.decode(Data(json.utf8))
        #expect(deck.cards.first?.hint == "")
        #expect(deck.cards.first?.learningState == nil)
        #expect(deck.learningOptions == LearningOptions())
    }

    @Test func clampsInvalidLearningOptions() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 3, "progress": [], "cards": [],
         "learningOptions": {"targetRecall": 0, "steps": 0, "maximumInterval": -5, "cardsPerSession": 0}}
        """
        let learningOptions = try DeckFile.decode(Data(json.utf8)).learningOptions
        #expect(learningOptions.targetRecall == LearningOptions.targetRecallRange.lowerBound)
        #expect(learningOptions.steps == 1)
        #expect(learningOptions.maximumInterval == 1)
        #expect(learningOptions.cardsPerSession == 1)
    }

    @Test func rejectsForeignAndFutureFiles() {
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(Data("{\"foo\": 1}".utf8)) }
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(Data("not json".utf8)) }
        let future = Data("{\"format\": \"com.mfluch.voctrain.deck\", \"version\": 99}".utf8)
        #expect(throws: DeckFile.Error.unsupportedVersion(99)) { try DeckFile.decode(future) }
    }
}

struct ReviewLogEncoderTests {
    let date = Date(timeIntervalSince1970: 1_791_216_000)

    func cards(_ count: Int) -> [Card] {
        (0..<count).map { index in
            var card = Card(question: "q\(index)", answer: "a\(index)")
            card.log = (0..<3).map { ReviewLogEntry(date: date.addingTimeInterval(Double($0 * 86400 + index)), grade: .good) }
            return card
        }
    }

    /// Encodes with the cached encoder and checks it matches a fresh one.
    func encode(_ cards: [Card], with encoder: ReviewLogEncoder) -> Int {
        let data = encoder.encode(cards)
        #expect(data == ReviewLogEncoder().encode(cards))
        return encoder.lastEncodedCardCount
    }

    @Test func onlyChangedCardsAreEncodedAgain() {
        let encoder = ReviewLogEncoder()
        var deck = cards(50)
        #expect(encode(deck, with: encoder) == 50)
        #expect(encode(deck, with: encoder) == 0)

        deck[7].log.append(ReviewLogEntry(date: date.addingTimeInterval(10 * 86400), grade: .again))
        #expect(encode(deck, with: encoder) == 1)

        deck[7].log.removeLast() // undo
        #expect(encode(deck, with: encoder) == 1)

        deck[8].log = [] // reset
        #expect(encode(deck, with: encoder) == 0)

        deck.remove(at: 3) // delete
        deck.append(cards(1)[0]) // add a studied card
        #expect(encode(deck, with: encoder) == 1)
    }

    @Test func replacedLogOfSameLengthIsNoticed() {
        let encoder = ReviewLogEncoder()
        var deck = cards(2)
        _ = encode(deck, with: encoder)
        deck[0].log[2].grade = .easy
        #expect(encode(deck, with: encoder) == 1)
    }

    @Test func cardsWithoutReviewsWriteNothing() {
        #expect(ReviewLogEncoder().encode([Card(question: "q", answer: "a")]).isEmpty)
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

    func legacyStatus(_ date: Int, counters: [Int]) -> LegacyDailyStatus {
        let status = LegacyDailyStatus()
        status.date = date
        status.counters = counters.map { LegacyCounter(value: $0) }
        return status
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
                legacyCard("relearning", level: 0, lastAnswered: lastAnswered),
                legacyCard("known", level: 3, lastAnswered: lastAnswered, adjustment: 0.1),
            ],
            progress: []
        )
        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.cards.map(\.question) == ["new", "relearning", "known"])
        #expect(deck.cards[0].isNew)

        let relearning = try #require(deck.cards[1].learningState)
        #expect(relearning.phase == .relearning)
        #expect(deck.cards[1].isDue(at: now))
        #expect(relearning.reviews == 1)

        let known = try #require(deck.cards[2].learningState)
        #expect(known.phase == .review)
        #expect(abs(known.stability - 1.8 * 1.1) < 1e-6)
        #expect(abs(known.due.timeIntervalSince(lastAnswered) - 1.8 * 1.1 * 86400) < 1)
        #expect(deck.cards[2].hint == "hint")
        #expect(deck.cards[2].answer == "answer of known")
        // Reviews before the import are missing from the log, also after the next one.
        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        for card in deck.cards.dropFirst() {
            #expect(!scheduler.review(card, grade: .good, at: now).hasCompleteLog)
        }
    }

    @Test func importsProgress() throws {
        let data = try legacyArchive(
            cards: [legacyCard("x", level: 0, lastAnswered: nil)],
            progress: [legacyStatus(20_141_108, counters: [5, 2, 0, 1])]
        )

        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.progress.count == 2)
        let first = deck.progress[0]
        #expect(CivilDate(dayNumber: first.day).isoString == "2014-11-08")
        #expect(first.bins[0] == 1)  // level 0, up to the cards never asked
        #expect(first.bins[1] == 6)  // the rest of level 0 and level 1 (0.7 days)
        #expect(first.bins[2] == 1)  // level 3 (1.8 days)
        #expect(deck.progress[1].day == calendar.dayNumber(for: now))
    }

    @Test func importedProgressContinuesOnImportDay() throws {
        let lastAnswered = now.addingTimeInterval(-86400)
        let data = try legacyArchive(
            cards: [
                legacyCard("new", level: 0, lastAnswered: nil),
                legacyCard("also new", level: 0, lastAnswered: nil),
                legacyCard("relearning", level: 0, lastAnswered: lastAnswered),
                legacyCard("known", level: 3, lastAnswered: lastAnswered),
            ],
            progress: [
                legacyStatus(20_141_107, counters: [1]),
                legacyStatus(20_141_108, counters: [3, 0, 0, 1]),
            ]
        )

        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.progress.count == 3)
        // Before the other cards were added: fewer cards at level 0 than never asked.
        #expect(deck.progress[0].bins[0] == 1)
        #expect(deck.progress[0].bins[1] == 0)
        // Saved together with the cards, the last old day matches import day.
        let lastOld = deck.progress[1], importDay = deck.progress[2]
        #expect(importDay.day == calendar.dayNumber(for: now))
        #expect(lastOld.bins[0] == 2)
        #expect(lastOld.bins == importDay.bins)
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
        print("Imported \(deck.cards.count) cards, \(deck.progress.count) history entries")
        print("New: \(deck.cards.filter(\.isNew).count), due now: \(deck.cards.filter { $0.isDue(at: Date()) }.count)")
        #expect(!deck.cards.isEmpty)
        #expect(deck.cards.allSatisfy { !$0.question.isEmpty })
    }
}
