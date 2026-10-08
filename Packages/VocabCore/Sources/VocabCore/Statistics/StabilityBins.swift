import Foundation

/// Histogram of cards by stability, with bins doubling in width.
///
/// - Bin 0: new cards
/// - Bin 1: cards in (re)learning or with stability below one day
/// - Bin 2…11: stability in [1, 2), [2, 4), [4, 8), … days; bin 11 is open-ended
///
/// The fine, fixed bins are what gets stored in the progress. How they are grouped
/// for display (`MaturityCategory`) can change without touching stored data.
public enum StabilityBins {
    public static let count = 12

    public static func bin(forStability stability: Double) -> Int {
        guard stability >= 1 else { return 1 }
        // Capped before the conversion, which traps for an infinite stability.
        return Int(min(2 + log2(stability).rounded(.down), Double(count - 1)))
    }

    public static func bin(for card: Card) -> Int {
        guard let learningState = card.learningState else { return 0 }
        guard learningState.phase == .review else { return 1 }
        return bin(forStability: learningState.stability)
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
    case shaky
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
        case 1...3: self = .shaky
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
