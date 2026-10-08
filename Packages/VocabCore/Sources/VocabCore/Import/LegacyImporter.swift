import Foundation

/// Imports documents of MacVocTrain 1 (`.mvt`, an NSKeyedArchiver archive).
///
/// The old app used a fixed level system: a card at level *n* became due a fixed
/// time after it was last asked and known (0.7 days at level 1 up to 22 days at level
/// 12, then 3.52 days more per level), spread by ±10 %. Level 0 meant "not known".
///
/// Conversion to FSRS:
/// - never asked → new card
/// - level 0 → relearning, due immediately
/// - level n ≥ 1 → card in the review phase whose stability equals its old interval, so it falls
///   due exactly when MacVocTrain 1 would have asked it. Difficulty is unknown and
///   set to a neutral 5; FSRS adapts it with the first reviews.
///
/// Damaged values are clamped so the deck saves, opens and studies:
/// - The interval including spread is at most the `maximumInterval` of the new deck,
///   which the scheduler never exceeds either.
/// - The level counts as at most as many reviews as the lowest level reaching that interval.
/// - A `lastAnswered` after `now`, before 2001 or not finite becomes `now`.
///
/// The daily level statistics become the progress of the deck. Their counter for level 0
/// holds both cards never asked and cards answered wrong; see `progress(from:neverAsked:)`.
public enum LegacyImporter {
    public enum Error: Swift.Error, Equatable {
        case unreadableArchive
    }

    public static let neutralDifficulty = 5.0

    /// The earliest plausible `lastAnswered`: MacVocTrain 1 wrote its documents with
    /// `NSKeyedArchiver`, which exists since Mac OS X 10.2.
    static let earliestAnswer = Date(timeIntervalSinceReferenceDate: 0)

    public static func importDeck(from data: Data, now: Date = Date(), calendar: StudyCalendar = StudyCalendar()) throws -> Deck {
        let box = try unarchive(data)
        let fsrs = FSRS()
        let learningOptions = LearningOptions()
        // Longer intervals the scheduler never plans either.
        let maximumDays = Double(learningOptions.maximumInterval)
        let maximumLevel = lowestLevel(reaching: maximumDays)

        let cards = box.indexCards.map { legacy -> Card in
            var card = Card(
                question: legacy.question ?? "",
                answer: legacy.answer ?? "",
                hint: legacy.remarkQuestion ?? "",
                created: now
            )
            if var lastAnswered = legacy.lastAnswered {
                // A damaged date (also NaN) counts as answered at import.
                if !(lastAnswered >= earliestAnswer && lastAnswered <= now) {
                    lastAnswered = now
                }
                if legacy.level <= 0 {
                    card.learningState = LearningState(
                        phase: .relearning,
                        stability: fsrs.initialStability(.again),
                        difficulty: fsrs.initialDifficulty(.again),
                        lastReview: lastAnswered,
                        due: lastAnswered,
                        // Asked at least once; the log of that review is missing.
                        reviews: 1
                    )
                } else {
                    // MacVocTrain 1 used ±10 %; clamp in case the file is damaged.
                    let adjustment = Double(legacy.levelDurationAdjustment)
                    let days = levelDuration(legacy.level) * (1 + (adjustment.isFinite ? min(max(adjustment, -0.5), 0.5) : 0))
                    let interval = min(days, maximumDays)
                    card.learningState = LearningState(
                        phase: .review,
                        stability: interval,
                        difficulty: neutralDifficulty,
                        lastReview: lastAnswered,
                        due: lastAnswered.addingTimeInterval(interval * 86400),
                        reviews: min(legacy.level, maximumLevel)
                    )
                }
            }
            return card
        }

        let statuses = box.progressMonitor?.progressData ?? []
        var deck = Deck(learningOptions: learningOptions, cards: cards, progress: progress(from: statuses, neverAsked: cards.filter(\.isNew).count))
        deck.updateProgress(day: calendar.dayNumber(for: now))
        return deck
    }

    private static let levelDurations = [0.7, 1.5, 1.8, 2.5, 3.5, 4.5, 6.5, 9.5, 13.5, 15.5, 18.5, 22.0]
    private static let levelIncrement = 3.52

    /// Interval of a level in days, as defined by `LevelDefinitions` in MacVocTrain 1.
    public static func levelDuration(_ level: Int) -> Double {
        guard level >= 1 else { return Double(level) * levelIncrement }
        guard level > levelDurations.count else { return levelDurations[level - 1] }
        return levelDurations[levelDurations.count - 1] + Double(level - levelDurations.count) * levelIncrement
    }

    /// The lowest level whose interval is at least `days`.
    static func lowestLevel(reaching days: Double) -> Int {
        if let index = levelDurations.firstIndex(where: { $0 >= days }) { return index + 1 }
        let beyond = (days - levelDurations[levelDurations.count - 1]) / levelIncrement
        return levelDurations.count + Int(beyond.rounded(.up))
    }

    /// Converts the daily level statistics into snapshots.
    ///
    /// MacVocTrain 1 counted new cards and cards answered wrong together as level 0, so the
    /// split into new and shaky is estimated: up to `neverAsked` (the cards never asked at
    /// import) count as new, the rest as shaky. A card never asked at import was never asked
    /// on any earlier day it existed, so the split is exact on the last old day and does not
    /// jump on import day. On days before some of those cards were added, cards answered
    /// wrong count as new in their place.
    ///
    /// Every level from 1 counts with the interval of the level, without spread. The
    /// snapshot of import day comes from the cards, whose stability includes the ±10 % that
    /// MacVocTrain 1 stored per card. Where that spread crosses a bin boundary, the card
    /// changes its bin on import day, at 4, 16, 64 or 256 days also its maturity.
    static func progress(from statuses: [LegacyDailyStatus], neverAsked: Int) -> [DailySnapshot] {
        var snapshots: [Int: DailySnapshot] = [:]
        for status in statuses {
            let date = CivilDate(year: status.date / 10000, month: (status.date / 100) % 100, day: status.date % 100)
            guard (1...12).contains(date.month), (1...31).contains(date.day) else { continue }
            var bins = [Int](repeating: 0, count: StabilityBins.count)
            for (level, counter) in status.counters.enumerated() {
                if level == 0 {
                    let new = min(counter.value, neverAsked)
                    bins[0] += new
                    bins[1] += counter.value - new
                } else {
                    bins[StabilityBins.bin(forStability: levelDuration(level))] += counter.value
                }
            }
            snapshots[date.dayNumber] = DailySnapshot(day: date.dayNumber, bins: bins.map { max(0, $0) })
        }
        return snapshots.values.sorted { $0.day < $1.day }
    }

    static func unarchive(_ data: Data) throws -> LegacyBox {
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw Error.unreadableArchive
        }
        defer { unarchiver.finishDecoding() }
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        for entry in LegacyClasses.mapping {
            unarchiver.setClass(entry.1, forClassName: entry.0)
        }
        // A damaged part sets the error but may leave the rest readable.
        guard let box = unarchiver.decodeObject(of: LegacyBox.self, forKey: NSKeyedArchiveRootObjectKey), unarchiver.error == nil else {
            throw Error.unreadableArchive
        }
        return box
    }
}

// MARK: - Archived classes of MacVocTrain 1

enum LegacyClasses {
    /// Archived class names (including names from even older versions) and their stand-ins.
    static let mapping: [(String, AnyClass)] = [
        ("IndexCardBoxHelper", LegacyBox.self),
        ("MVTIndexCardBox", LegacyBox.self),
        ("IndexCard", LegacyIndexCard.self),
        ("MVTIndexCard", LegacyIndexCard.self),
        ("ProgressMonitor", LegacyProgressMonitor.self),
        ("DailyStatus", LegacyDailyStatus.self),
        ("Counter", LegacyCounter.self),
    ]

    static let arrayClasses: [AnyClass] = [NSArray.self, NSMutableArray.self]
}

final class LegacyBox: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    var indexCards: [LegacyIndexCard] = []
    var progressMonitor: LegacyProgressMonitor?

    override init() {}

    /// Fails without cards: a missing list or a foreign element in it means a damaged document.
    init?(coder: NSCoder) {
        guard let cards = coder.decodeObject(of: LegacyClasses.arrayClasses + [LegacyIndexCard.self], forKey: "indexCards") as? [LegacyIndexCard] else { return nil }
        indexCards = cards
        progressMonitor = coder.decodeObject(of: LegacyProgressMonitor.self, forKey: "progressMonitor")
    }

    func encode(with coder: NSCoder) {
        coder.encode(indexCards as NSArray, forKey: "indexCards")
        coder.encode(progressMonitor, forKey: "progressMonitor")
    }
}

final class LegacyIndexCard: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    var question: String?
    var answer: String?
    var remarkQuestion: String?
    var lastAnswered: Date?
    var level = 0
    var levelDurationAdjustment: Float = 0

    override init() {}

    init?(coder: NSCoder) {
        question = coder.decodeObject(of: NSString.self, forKey: "question") as String?
        answer = coder.decodeObject(of: NSString.self, forKey: "answer") as String?
        remarkQuestion = coder.decodeObject(of: NSString.self, forKey: "remarkQuestion") as String?
        lastAnswered = coder.decodeObject(of: NSDate.self, forKey: "lastAnswered") as Date?
        level = coder.decodeInteger(forKey: "level")
        levelDurationAdjustment = coder.decodeFloat(forKey: "levelDurationAdjustment")
    }

    func encode(with coder: NSCoder) {
        coder.encode(question, forKey: "question")
        coder.encode(answer, forKey: "answer")
        coder.encode(remarkQuestion, forKey: "remarkQuestion")
        coder.encode(lastAnswered, forKey: "lastAnswered")
        coder.encode(level, forKey: "level")
        coder.encode(levelDurationAdjustment, forKey: "levelDurationAdjustment")
    }
}

final class LegacyProgressMonitor: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    var progressData: [LegacyDailyStatus] = []

    override init() {}

    init?(coder: NSCoder) {
        progressData = coder.decodeObject(of: LegacyClasses.arrayClasses + [LegacyDailyStatus.self], forKey: "progressData") as? [LegacyDailyStatus] ?? []
    }

    func encode(with coder: NSCoder) {
        coder.encode(progressData as NSArray, forKey: "progressData")
    }
}

final class LegacyDailyStatus: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    /// Date as `yyyymmdd`.
    var date = 0
    /// Number of cards per level.
    var counters: [LegacyCounter] = []

    override init() {}

    init?(coder: NSCoder) {
        date = coder.decodeInteger(forKey: "date")
        counters = coder.decodeObject(of: LegacyClasses.arrayClasses + [LegacyCounter.self], forKey: "counters") as? [LegacyCounter] ?? []
    }

    func encode(with coder: NSCoder) {
        coder.encode(date, forKey: "date")
        coder.encode(counters as NSArray, forKey: "counters")
    }
}

final class LegacyCounter: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    var value = 0

    init(value: Int = 0) {
        self.value = value
    }

    init?(coder: NSCoder) {
        value = coder.decodeInteger(forKey: "value")
    }

    func encode(with coder: NSCoder) {
        coder.encode(value, forKey: "value")
    }
}
