import Foundation

/// Maps points in time to study days.
///
/// A study day starts at `rolloverHour` local time instead of midnight, so a late
/// evening session still belongs to the same day.
public struct StudyCalendar: Sendable {
    public var timeZone: TimeZone
    public var rolloverHour: Int

    public init(timeZone: TimeZone = .current, rolloverHour: Int = 4) {
        self.timeZone = timeZone
        self.rolloverHour = rolloverHour
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The study day containing `date`, as days since 1970-01-01.
    public func dayNumber(for date: Date) -> Int {
        let shifted = date.addingTimeInterval(-Double(rolloverHour) * 3600)
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return CivilDate(year: components.year!, month: components.month!, day: components.day!).dayNumber
    }

    /// The moment the given study day begins.
    public func start(ofDay dayNumber: Int) -> Date {
        let civil = CivilDate(dayNumber: dayNumber)
        let components = DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: rolloverHour)
        return calendar.date(from: components)!
    }

    /// Whole study days from `start` to `end`; 0 when both fall on the same study day.
    public func days(from start: Date, to end: Date) -> Int {
        dayNumber(for: end) - dayNumber(for: start)
    }
}
