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
        // One review short, like a card imported from MacVocTrain 1 with a learning state.
        card.log = [ReviewLogEntry(date: date.addingTimeInterval(-86400), grade: .again), ReviewLogEntry(date: date, grade: .hard)]
        return Deck(learningOptions: learningOptions, cards: [card, Card(question: "kot", answer: "Katze", created: date)], progress: [DailySnapshot(day: 20_000, bins: [1, 1])])
    }

    func file(_ wrapper: FileWrapper, _ name: String) -> String {
        String(decoding: wrapper.fileWrappers![name]!.regularFileContents!, as: UTF8.self)
    }

    /// The package of `deck` with `lines` appended to its `reviews.jsonl`.
    func package(of deck: Deck, appendingReviews lines: [String]) throws -> FileWrapper {
        let wrapper = try DeckFile.fileWrapper(for: deck)
        let reviews = file(wrapper, DeckFile.reviewsFileName) + lines.map { $0 + "\n" }.joined()
        wrapper.removeFileWrapper(wrapper.fileWrappers![DeckFile.reviewsFileName]!)
        wrapper.addRegularFile(withContents: Data(reviews.utf8), preferredFilename: DeckFile.reviewsFileName)
        return wrapper
    }

    func reviewLine(of id: Card.ID) -> String {
        "{\"card\":\"\(id.uuidString)\",\"date\":1791216000,\"grade\":3}"
    }

    /// A `deck.json` with one card whose learning state has the given values.
    func deckJSON(step: Int = 0, stability: Double = 12.5, difficulty: Double = 5, reviews: Int = 1, lapses: Int = 0, parameters: [Double] = FSRSParameters.default.weights) -> Data {
        let learningState = """
            {"phase": "review", "step": \(step), "stability": \(stability), "difficulty": \(difficulty),
             "lastReview": "2026-10-05T16:00:00Z", "due": "2026-10-06T02:00:00Z", "reviews": \(reviews), "lapses": \(lapses)}
            """
        let json = """
            {"format": "com.mfluch.voctrain.deck", "version": 3, "progress": [], "learningOptions": {"parameters": \(parameters)},
             "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus", "learningState": \(learningState)}]}
            """
        return Data(json.utf8)
    }

    @Test func packageRoundTripPreservesEverything() throws {
        let deck = sampleDeck()
        #expect(try DeckFile.decode(DeckFile.fileWrapper(for: deck)) == deck)
    }

    /// A `deck.json` of version 3 as the app writes it, with every kind of value.
    @Test func fixedDeckReadsAndWritesBackUnchanged() throws {
        let url = try #require(Bundle.module.url(forResource: "Resources/deck-v3", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let deck = try DeckFile.decode(data)

        #expect(deck.cards.map(\.question) == ["dom", "pies", "kot"])
        #expect(deck.cards[0].hint == "Substantiv")
        #expect(deck.cards[0].created == date.addingTimeInterval(-7 * 86400))
        #expect(deck.cards[1].learningState?.phase == .relearning)
        #expect(deck.cards[1].learningState?.due == date.addingTimeInterval(600))
        #expect(deck.cards[2].isNew)
        #expect(deck.learningOptions.cardsPerSession == nil)
        #expect(deck.learningOptions.newCardsPerSession == 15)
        #expect(deck.learningOptions.parameters == .default)
        #expect(deck.progress.map(\.day) == [CivilDate(isoString: "2026-10-04")!.dayNumber, CivilDate(isoString: "2026-10-05")!.dayNumber])

        #expect(String(decoding: try DeckFile.encodeDeck(deck), as: UTF8.self) == String(decoding: data, as: UTF8.self))
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
        #expect(
            file(wrapper, DeckFile.reviewsFileName) == """
                {"card":"\(id)","date":1791129600,"grade":1}
                {"card":"\(id)","date":1791216000,"grade":2}

                """)
    }

    @Test func rejectsVersionsBeforeTheFirstRelease() {
        let version1 = Data(
            """
            {"format": "com.mfluch.voctrain.deck", "version": 1, "settings": {}, "history": [],
             "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus",
                        "created": "2026-10-05T16:00:00Z", "log": [{"date": "2026-10-05T16:00:00Z", "grade": 3}]}]}
            """.utf8)
        #expect(throws: DeckFile.Error.outdatedVersion(1)) { try DeckFile.decode(FileWrapper(regularFileWithContents: version1)) }

        let version2 = Data(
            """
            {"format": "com.mfluch.voctrain.deck", "version": 2, "settings": {}, "history": [], "cards": []}
            """.utf8)
        let package = FileWrapper(directoryWithFileWrappers: [DeckFile.deckFileName: FileWrapper(regularFileWithContents: version2)])
        #expect(throws: DeckFile.Error.outdatedVersion(2)) { try DeckFile.decode(package) }
    }

    @Test func singleFileOfCurrentVersionIsNoDeck() throws {
        let deckJSON = try DeckFile.encodeDeck(sampleDeck())
        #expect(throws: DeckFile.Error.notADeck) { try DeckFile.decode(FileWrapper(regularFileWithContents: deckJSON)) }
    }

    @Test func packageWithoutReviewLogIsRejectedOnceACardWasStudied() throws {
        let wrapper = try DeckFile.fileWrapper(for: sampleDeck())
        wrapper.removeFileWrapper(wrapper.fileWrappers![DeckFile.reviewsFileName]!)
        #expect(throws: DeckFile.Error.missingReviewLog) { try DeckFile.decode(wrapper) }
    }

    @Test func packageWithoutReviewLogOpensWhileAllCardsAreNew() throws {
        let deck = Deck(cards: [Card(question: "kot", answer: "Katze", created: date)])
        let wrapper = try DeckFile.fileWrapper(for: deck)
        wrapper.removeFileWrapper(wrapper.fileWrappers![DeckFile.reviewsFileName]!)
        #expect(try DeckFile.decode(wrapper) == deck)
    }

    @Test func reviewsOfUnknownCardsAreRejected() throws {
        let deck = sampleDeck()
        let wrapper = try package(of: deck, appendingReviews: [reviewLine(of: UUID())])
        #expect(throws: DeckFile.Error.reviewsOfUnknownCard(line: 3)) { try DeckFile.decode(wrapper) }

        let reviews = Data(file(try DeckFile.fileWrapper(for: deck), DeckFile.reviewsFileName).utf8)
        var remaining = [deck.cards[1]]  // the card with reviews was deleted
        #expect(throws: DeckFile.Error.reviewsOfUnknownCard(line: 1)) { try ReviewLogEncoder.attach(reviews, to: &remaining) }
    }

    @Test func reviewLogLongerThanReviewsIsRejected() throws {
        let deck = sampleDeck()
        let studied = deck.cards[0]
        let tooLong = try package(of: deck, appendingReviews: [reviewLine(of: studied.id), reviewLine(of: studied.id)])
        #expect(throws: DeckFile.Error.reviewLogTooLong(question: "dom")) { try DeckFile.decode(tooLong) }

        let ofNewCard = try package(of: deck, appendingReviews: [reviewLine(of: deck.cards[1].id)])
        #expect(throws: DeckFile.Error.reviewLogTooLong(question: "kot")) { try DeckFile.decode(ofNewCard) }
    }

    @Test func reviewLogShorterThanReviewsIsAllowed() throws {
        let deck = sampleDeck()
        let card = try DeckFile.decode(DeckFile.fileWrapper(for: deck)).cards[0]
        #expect(card.log == deck.cards[0].log)
        #expect(card.log.count < card.learningState!.reviews)
    }

    @Test func duplicateCardIDsAreRejected() throws {
        var deck = sampleDeck()
        deck.cards.append(Card(id: deck.cards[1].id, question: "kot", answer: "Kater", created: date))
        #expect(throws: DeckFile.Error.duplicateCardID(question: "kot")) { try DeckFile.decode(DeckFile.fileWrapper(for: deck)) }
        #expect(throws: DeckFile.Error.duplicateCardID(question: "kot")) { try DeckFile.decode(DeckFile.encodeDeck(deck)) }
    }

    @Test func parametersOutOfRangeAreRejected() throws {
        var weights = FSRSParameters.default.weights
        weights[20] = 0.001
        #expect(throws: DeckFile.Error.parameterOutOfRange(index: 20)) { try DeckFile.decode(deckJSON(parameters: weights)) }

        // Above the ceiling the optimizer sets for several learning steps, but within the fixed one.
        weights = FSRSParameters.default.weights
        weights[17] = 2
        weights[18] = 2
        #expect(try DeckFile.decode(deckJSON(parameters: weights)).learningOptions.parameters.weights == weights)
    }

    /// Values the app never writes are clamped, so studying the card neither crashes
    /// nor yields values the deck can't be saved with.
    @Test(arguments: [
        (step: 0, stability: 0.0, difficulty: 5.0, reviews: 1, lapses: 0),
        (step: 0, stability: 12.5, difficulty: -3.0, reviews: 1, lapses: 0),
        (step: 0, stability: 12.5, difficulty: 50.0, reviews: 1, lapses: 0),
        (step: 0, stability: 12.5, difficulty: 5.0, reviews: Int.max, lapses: Int.max),
        (step: -2, stability: 12.5, difficulty: 5.0, reviews: -1, lapses: -1),
        (step: Int.max, stability: 1e300, difficulty: 5.0, reviews: 1, lapses: 0),
    ])
    func learningStateOutOfRangeIsClamped(values: (step: Int, stability: Double, difficulty: Double, reviews: Int, lapses: Int)) throws {
        let json = deckJSON(step: values.step, stability: values.stability, difficulty: values.difficulty, reviews: values.reviews, lapses: values.lapses)
        let deck = try DeckFile.decode(json)
        let learningState = try #require(deck.cards[0].learningState)
        #expect(learningState.stability >= FSRS.minimumStability)
        #expect(FSRS.difficultyRange.contains(learningState.difficulty))
        #expect(learningState.step >= 0 && learningState.reviews >= 0 && learningState.lapses >= 0)

        for phase in [LearningPhase.review, .relearning] {
            for days in [0.0, 3, 400] {
                for grade in [Grade.good, .easy, .again] {
                    var studied = deck
                    studied.cards[0].learningState?.phase = phase
                    var random = SeededRandom(seed: 1)
                    let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: .testing)
                    studied.cards[0] = scheduler.review(studied.cards[0], grade: grade, at: date.addingTimeInterval(days * 86400), using: &random)
                    let reviewed = try #require(studied.cards[0].learningState)
                    #expect(reviewed.stability.isFinite && reviewed.difficulty.isFinite, "\(phase) \(grade) after \(days) days")
                    // Values at the upper bounds are clamped again, so the deck itself may differ.
                    #expect(try DeckFile.decode(DeckFile.fileWrapper(for: studied)).cards[0].log == studied.cards[0].log)
                }
            }
        }
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

    /// What a newer app version adds without a new format version, an older one reads
    /// and drops on the next save (see `DeckFile`).
    @Test func unknownKeysAndFilesAreReadAndDroppedOnSave() throws {
        let deckJSON = """
            {"format": "com.mfluch.voctrain.deck", "version": 3, "progress": [], "futureDeckKey": 1,
             "learningOptions": {"targetRecall": 0.85, "futureOption": 7},
             "cards": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "question": "dom", "answer": "Haus", "futureCardKey": "x",
                        "learningState": {"phase": "learning", "step": 1, "stability": 2.3, "difficulty": 2.1, "reviews": 1, "lapses": 0,
                                          "lastReview": "2026-10-05T16:00:00Z", "due": "2026-10-05T16:00:00Z"}}]}
            """
        let reviews = """
            {"card":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":1791216000,"grade":3,"futureReviewKey":true}

            """
        let package = FileWrapper(directoryWithFileWrappers: [
            DeckFile.deckFileName: FileWrapper(regularFileWithContents: Data(deckJSON.utf8)),
            DeckFile.reviewsFileName: FileWrapper(regularFileWithContents: Data(reviews.utf8)),
            "future.json": FileWrapper(regularFileWithContents: Data("{}".utf8)),
        ])

        let deck = try DeckFile.decode(package)
        #expect(deck.learningOptions.targetRecall == 0.85)
        #expect(deck.cards.map(\.question) == ["dom"])
        #expect(deck.cards[0].log == [ReviewLogEntry(date: date, grade: .good)])

        let written = try DeckFile.fileWrapper(for: deck)
        #expect(Set(written.fileWrappers!.keys) == [DeckFile.deckFileName, DeckFile.reviewsFileName])
        let writtenDeck = file(written, DeckFile.deckFileName)
        for key in ["futureDeckKey", "futureOption", "futureCardKey"] {
            #expect(!writtenDeck.contains(key), "kept key \(key)")
        }
        #expect(file(written, DeckFile.reviewsFileName) == "{\"card\":\"6F9619FF-8B86-D011-B42D-00C04FC964FF\",\"date\":1791216000,\"grade\":3}\n")
    }

    @Test func clampsInvalidLearningOptions() throws {
        let json = """
            {"format": "com.mfluch.voctrain.deck", "version": 3, "progress": [], "cards": [],
             "learningOptions": {"targetRecall": 0, "steps": 0, "maximumInterval": -5, "cardsPerSession": 0,
                                 "newCardsPerSession": 100000}}
            """
        let learningOptions = try DeckFile.decode(Data(json.utf8)).learningOptions
        #expect(learningOptions.targetRecall == LearningOptions.targetRecallRange.lowerBound)
        #expect(learningOptions.steps == LearningOptions.stepsRange.lowerBound)
        #expect(learningOptions.maximumInterval == LearningOptions.maximumIntervalRange.lowerBound)
        #expect(learningOptions.cardsPerSession == LearningOptions.sessionLimitRange.lowerBound)
        #expect(learningOptions.newCardsPerSession == LearningOptions.sessionLimitRange.upperBound)
    }

    @Test func rejectsInvalidValues() {
        let parameters = """
            {"format": "com.mfluch.voctrain.deck", "version": 3, "progress": [], "cards": [],
             "learningOptions": {"parameters": [1, 2]}}
            """
        #expect(throws: DecodingError.self) { try DeckFile.decode(Data(parameters.utf8)) }

        let day = """
            {"format": "com.mfluch.voctrain.deck", "version": 3, "learningOptions": {}, "cards": [],
             "progress": [{"day": "2026-13-45", "bins": []}]}
            """
        #expect(throws: DecodingError.self) { try DeckFile.decode(Data(day.utf8)) }
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

        deck[7].log.removeLast()  // undo
        #expect(encode(deck, with: encoder) == 1)

        deck[8].log = []  // reset
        #expect(encode(deck, with: encoder) == 0)

        deck.remove(at: 3)  // delete
        deck.append(cards(1)[0])  // add a studied card
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
    let calendar = StudyCalendar.testing
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
        var random = SeededRandom(seed: 1)
        for card in deck.cards.dropFirst() {
            #expect(!scheduler.review(card, grade: .good, at: now, using: &random).hasCompleteLog)
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
        let lastOld = deck.progress[1]
        let importDay = deck.progress[2]
        #expect(importDay.day == calendar.dayNumber(for: now))
        #expect(lastOld.bins[0] == 2)
        #expect(lastOld.bins == importDay.bins)
    }

    /// Old snapshots count a level without spread, import day counts the card with it.
    @Test func spreadMovesImportedCardToMaturingOnImportDay() throws {
        let data = try legacyArchive(
            // Level 10 is 15.5 days, +5 % makes 16.3 days.
            cards: [legacyCard("known", level: 10, lastAnswered: now.addingTimeInterval(-86400), adjustment: 0.05)],
            progress: [legacyStatus(20_141_108, counters: Array(repeating: 0, count: 10) + [1])]
        )

        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        #expect(deck.progress.count == 2)
        let lastOld = MaturityCategory.counts(fromBins: deck.progress[0].bins)
        let importDay = MaturityCategory.counts(fromBins: deck.progress[1].bins)
        #expect(lastOld[.young] == 1)
        #expect(lastOld[.maturing] == 0)
        #expect(importDay[.young] == 0)
        #expect(importDay[.maturing] == 1)
    }

    @Test func rejectsGarbage() {
        #expect(throws: LegacyImporter.Error.unreadableArchive) {
            try LegacyImporter.importDeck(from: Data("nope".utf8))
        }
    }

    /// Builds an archive like `legacyArchive` whose `indexCards` hold `elements`, or lack the key if `nil`.
    func damagedLegacyArchive(indexCards elements: [NSObject]?) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("IndexCardBoxHelper", for: DamagedLegacyBox.self)
        archiver.setClassName("IndexCard", for: LegacyIndexCard.self)
        archiver.setClassName("MVTFlashcard", for: UnknownLegacyElement.self)
        archiver.encode(DamagedLegacyBox(indexCards: elements.map { $0 as NSArray }), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    @Test func rejectsMissingCards() {
        #expect(throws: LegacyImporter.Error.unreadableArchive) {
            try LegacyImporter.importDeck(from: damagedLegacyArchive(indexCards: nil), now: now, calendar: calendar)
        }
    }

    @Test func rejectsForeignElementAmongCards() {
        let cards = [legacyCard("a", level: 0, lastAnswered: nil), legacyCard("b", level: 0, lastAnswered: nil)]
        #expect(throws: LegacyImporter.Error.unreadableArchive) {
            try LegacyImporter.importDeck(from: damagedLegacyArchive(indexCards: cards + ["stray" as NSString]), now: now, calendar: calendar)
        }
    }

    @Test func rejectsUnknownClassAmongCards() {
        let cards = [legacyCard("a", level: 0, lastAnswered: nil), legacyCard("b", level: 0, lastAnswered: nil)]
        #expect(throws: LegacyImporter.Error.unreadableArchive) {
            try LegacyImporter.importDeck(from: damagedLegacyArchive(indexCards: cards + [UnknownLegacyElement()]), now: now, calendar: calendar)
        }
    }

    /// Damaged levels and dates still give a deck that saves, opens and studies.
    @Test func clampsImplausibleLevelsAndDates() throws {
        let yesterday = now.addingTimeInterval(-86400)
        let data = try legacyArchive(
            cards: [
                legacyCard("huge level", level: 100_000_000, lastAnswered: yesterday),
                legacyCard("maximum level", level: .max, lastAnswered: yesterday),
                // Years 200 000 and -27; level 12 is 22 days, so due falls on whole seconds.
                legacyCard("far future", level: 12, lastAnswered: Date(timeIntervalSinceReferenceDate: 6_248_300_000_000)),
                legacyCard("before year 1", level: 12, lastAnswered: Date(timeIntervalSinceReferenceDate: -64_000_000_000)),
            ],
            progress: []
        )
        let deck = try LegacyImporter.importDeck(from: data, now: now, calendar: calendar)
        let maximumInterval = Double(deck.learningOptions.maximumInterval)

        for card in deck.cards {
            let learningState = try #require(card.learningState)
            try #require(learningState.stability <= maximumInterval, "\(card.question)")
            try #require(learningState.due.timeIntervalSince(learningState.lastReview) <= maximumInterval * 86400, "\(card.question)")
            try #require(learningState.lastReview <= now, "\(card.question)")
        }
        let maximumLevel = LegacyImporter.lowestLevel(reaching: maximumInterval)
        #expect(LegacyImporter.levelDuration(maximumLevel) >= maximumInterval)
        #expect(LegacyImporter.levelDuration(maximumLevel - 1) < maximumInterval)
        #expect(deck.cards[1].learningState?.reviews == maximumLevel)
        #expect(deck.cards[0].learningState?.lastReview == yesterday)
        #expect(deck.cards[2].learningState?.lastReview == now)
        #expect(deck.cards[3].learningState?.lastReview == now)
        // Saved and opened again, the dates stay as imported.
        #expect(try DeckFile.decode(DeckFile.fileWrapper(for: deck)) == deck)

        let scheduler = Scheduler(learningOptions: deck.learningOptions, calendar: calendar)
        var random = SeededRandom(seed: 1)
        for card in deck.cards {
            #expect(scheduler.review(card, grade: .good, at: now, using: &random).learningState?.phase == .review)
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

/// The root of a damaged MacVocTrain 1 document: any `indexCards`, or none.
final class DamagedLegacyBox: NSObject, NSCoding {
    let indexCards: NSArray?

    init(indexCards: NSArray?) {
        self.indexCards = indexCards
    }

    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        if let indexCards { coder.encode(indexCards, forKey: "indexCards") }
    }
}

/// An archived element whose class name MacVocTrain 1 never wrote.
final class UnknownLegacyElement: NSObject, NSCoding {
    override init() {}

    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {}
}
