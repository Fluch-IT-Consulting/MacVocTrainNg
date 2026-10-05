import Foundation

/// Imports documents of MacVocTrain 1 (`.mvt`, an NSKeyedArchiver archive).
///
/// The old app used a fixed level system: a card at level *n* became due a fixed
/// time after its last correct answer (0.7 days at level 1 up to 22 days at level
/// 12, then 3.52 days more per level), spread by ±10 %. Level 0 meant "not known".
///
/// Conversion to FSRS:
/// - never answered → new card
/// - level 0 → relearning, due immediately
/// - level n ≥ 1 → review card whose stability equals its old interval, so it falls
///   due exactly when MacVocTrain 1 would have asked it. Difficulty is unknown and
///   set to a neutral 5; FSRS adapts it with the first answers.
/// The daily level statistics are converted into stability histograms.
public enum LegacyImporter {
    public enum Error: Swift.Error, Equatable {
        case unreadableArchive
    }

    public static let neutralDifficulty = 5.0

    public static func importDeck(from data: Data, now: Date = Date(), calendar: StudyCalendar = StudyCalendar()) throws -> Deck {
        let box = try unarchive(data)
        let fsrs = FSRS()

        let cards = box.indexCards.map { legacy -> Card in
            var card = Card(
                question: legacy.question ?? "",
                answer: legacy.answer ?? "",
                remark: legacy.remarkQuestion ?? "",
                created: now
            )
            if let lastAnswered = legacy.lastAnswered {
                if legacy.level <= 0 {
                    card.memory = MemoryState(
                        phase: .relearning,
                        stability: fsrs.initialStability(.again),
                        difficulty: fsrs.initialDifficulty(.again),
                        lastReview: lastAnswered,
                        due: lastAnswered
                    )
                } else {
                    let days = levelDuration(legacy.level) * (1 + Double(legacy.levelDurationAdjustment))
                    card.memory = MemoryState(
                        phase: .review,
                        stability: days,
                        difficulty: neutralDifficulty,
                        lastReview: lastAnswered,
                        due: lastAnswered.addingTimeInterval(days * 86400),
                        reps: legacy.level
                    )
                }
            }
            return card
        }

        var deck = Deck(cards: cards, history: history(from: box.progressMonitor?.progressData ?? []))
        deck.updateHistory(day: calendar.dayNumber(for: now))
        return deck
    }

    /// Interval of a level in days, as defined by `LevelDefinitions` in MacVocTrain 1.
    public static func levelDuration(_ level: Int) -> Double {
        let levels = [0.7, 1.5, 1.8, 2.5, 3.5, 4.5, 6.5, 9.5, 13.5, 15.5, 18.5, 22.0]
        let increment = 3.52
        guard level >= 1 else { return Double(level) * increment }
        guard level > levels.count else { return levels[level - 1] }
        return levels[levels.count - 1] + Double(level - levels.count) * increment
    }

    static func history(from statuses: [LegacyDailyStatus]) -> [DailySnapshot] {
        var snapshots: [Int: DailySnapshot] = [:]
        for status in statuses {
            let date = CivilDate(year: status.date / 10000, month: (status.date / 100) % 100, day: status.date % 100)
            guard (1...12).contains(date.month), (1...31).contains(date.day) else { continue }
            var bins = [Int](repeating: 0, count: StabilityBins.count)
            for (level, counter) in status.counters.enumerated() {
                let bin = level == 0 ? 1 : StabilityBins.bin(forStability: levelDuration(level))
                bins[bin] += counter.value
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
        guard let box = unarchiver.decodeObject(of: LegacyBox.self, forKey: NSKeyedArchiveRootObjectKey) else {
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

    init?(coder: NSCoder) {
        indexCards = coder.decodeObject(of: LegacyClasses.arrayClasses + [LegacyIndexCard.self], forKey: "indexCards") as? [LegacyIndexCard] ?? []
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
