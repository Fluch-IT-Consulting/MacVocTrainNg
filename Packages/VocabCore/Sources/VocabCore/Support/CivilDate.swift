import Foundation

/// A calendar date without time or time zone, counted as days since 1970-01-01.
///
/// Uses the proleptic Gregorian calendar (algorithms by Howard Hinnant), so day
/// arithmetic is exact and unaffected by daylight saving time.
public struct CivilDate: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        day = doy - (153 * mp + 2) / 5 + 1
        month = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    }

    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.Component.weekday`.
    public static func weekday(ofDayNumber dayNumber: Int) -> Int {
        // 1970-01-01 was a Thursday (weekday 5).
        ((dayNumber % 7 + 7 + 4) % 7) + 1
    }

    /// ISO 8601 representation, e.g. `2026-10-05`.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool { lhs.dayNumber < rhs.dayNumber }
}
