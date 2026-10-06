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
        #expect(deckJSON.contains("\"version\" : 2"))
        #expect(deckJSON.contains("\"question\" : \"dom\""))
        #expect(!deckJSON.contains("\"log\""))
        #expect(!deckJSON.contains("\"remark\" : \"\""))

        let id = deck.cards[0].id.uuidString
        #expect(file(wrapper, DeckFile.reviewsFileName) == """
        {"card":"\(id)","date":1791129600,"grade":1}
        {"card":"\(id)","date":1791216000,"grade":2}

        """)
    }

    @Test func readsSingleFileOfVersion1() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 1, "settings": {}, "history": [],
         "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus",
                    "created": "2026-10-05T16:00:00Z", "log": [{"date": "2026-10-05T16:00:00Z", "grade": 3}]}]}
        """
        let deck = try DeckFile.decode(FileWrapper(regularFileWithContents: Data(json.utf8)))
        #expect(deck.cards.first?.log == [ReviewLogEntry(date: date, grade: .good)])

        // The next save writes it as a package with the log apart.
        let package = try DeckFile.fileWrapper(for: deck)
        #expect(try DeckFile.decode(package) == deck)
        #expect(!file(package, DeckFile.deckFileName).contains("\"log\""))
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

    @Test func packageReplacesSingleFileOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Stapel.voctrain")
        try Data("{}".utf8).write(to: url)

        let deck = sampleDeck()
        try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
        try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
        #expect(try DeckFile.decode(FileWrapper(url: url)) == deck)
    }

    @Test func optionalFieldsMayBeMissing() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 1, "settings": {},
         "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus"}],
         "history": []}
        """
        let deck = try DeckFile.decode(Data(json.utf8))
        #expect(deck.cards.first?.hint == "")
        #expect(deck.cards.first?.learningState == nil)
        #expect(deck.learningOptions == LearningOptions())
    }

    @Test func clampsInvalidLearningOptions() throws {
        let json = """
        {"format": "com.mfluch.voctrain.deck", "version": 1, "history": [], "cards": [],
         "settings": {"desiredRetention": 0, "learningSteps": 0, "maximumInterval": -5, "cardsPerSession": 0}}
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

        let known = try #require(deck.cards[2].learningState)
        #expect(known.phase == .review)
        #expect(abs(known.stability - 1.8 * 1.1) < 1e-6)
        #expect(abs(known.due.timeIntervalSince(lastAnswered) - 1.8 * 1.1 * 86400) < 1)
        #expect(deck.cards[2].hint == "hint")
        #expect(deck.cards[2].answer == "answer of known")
    }

    @Test func importsProgress() throws {
        let status = LegacyDailyStatus()
        status.date = 20_141_108
        status.counters = [LegacyCounter(value: 5), LegacyCounter(value: 2), LegacyCounter(value: 0), LegacyCounter(value: 1)]
        let data = try legacyArchive(cards: [legacyCard("x", level: 0, lastAnswered: nil)], progress: [status])

        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.progress.count == 2)
        let first = deck.progress[0]
        #expect(CivilDate(dayNumber: first.day).isoString == "2014-11-08")
        #expect(first.bins[1] == 7)  // level 0 and level 1 (0.7 days)
        #expect(first.bins[2] == 1)  // level 3 (1.8 days)
        #expect(deck.progress[1].day == calendar.dayNumber(for: now))
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
