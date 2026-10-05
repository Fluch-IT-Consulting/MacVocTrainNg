import Foundation

/// Histogram of cards by memory stability, with bins doubling in width.
///
/// - Bin 0: new cards
/// - Bin 1: cards in (re)learning or with stability below one day
/// - Bin 2…11: stability in [1, 2), [2, 4), [4, 8), … days; bin 11 is open-ended
///
/// The fine, fixed bins are what gets stored in the history. How they are grouped
/// for display (`MaturityCategory`) can change without touching stored data.
public enum StabilityBins {
    public static let count = 12

    public static func bin(forStability stability: Double) -> Int {
        guard stability >= 1 else { return 1 }
        let exponent = Int(log2(stability).rounded(.down))
        return min(2 + exponent, count - 1)
    }

    public static func bin(for card: Card) -> Int {
        guard let memory = card.memory else { return 0 }
        guard memory.phase == .review else { return 1 }
        return bin(forStability: memory.stability)
    }

    public static func histogram(of cards: [Card]) -> [Int] {
        var bins = [Int](repeating: 0, count: count)
        for card in cards {
            bins[bin(for: card)] += 1
        }
        return bins
    }
}

/// Coarse grouping of stability bins for charts and the card list.
public enum MaturityCategory: Int, CaseIterable, Comparable, Sendable {
    case new
    /// Stability below 4 days.
    case learning
    /// 4 to 16 days.
    case young
    /// 16 to 64 days.
    case maturing
    /// 64 to 256 days.
    case mature
    /// 256 days and more.
    case mastered

    public init(bin: Int) {
        switch bin {
        case ...0: self = .new
        case 1...3: self = .learning
        case 4...5: self = .young
        case 6...7: self = .maturing
        case 8...9: self = .mature
        default: self = .mastered
        }
    }

    public init(card: Card) {
        self.init(bin: StabilityBins.bin(for: card))
    }

    public static func counts(fromBins bins: [Int]) -> [MaturityCategory: Int] {
        var counts: [MaturityCategory: Int] = [:]
        for (bin, count) in bins.enumerated() {
            counts[MaturityCategory(bin: bin), default: 0] += count
        }
        return counts
    }

    public static func < (lhs: MaturityCategory, rhs: MaturityCategory) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The distribution of a deck's cards at the end of one study day.
public struct DailySnapshot: Hashable, Sendable {
    /// Study day as days since 1970-01-01.
    public var day: Int
    /// Card counts per `StabilityBins` bin.
    public var bins: [Int]

    public init(day: Int, bins: [Int]) {
        self.day = day
        self.bins = bins
    }

    public var total: Int { bins.reduce(0, +) }
}

extension DailySnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case day, bins }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .day)
        guard let date = CivilDate(isoString: text) else {
            throw DecodingError.dataCorruptedError(forKey: .day, in: container, debugDescription: "Invalid date \(text)")
        }
        day = date.dayNumber
        bins = try container.decode([Int].self, forKey: .bins)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CivilDate(dayNumber: day).isoString, forKey: .day)
        try container.encode(bins, forKey: .bins)
    }
}
