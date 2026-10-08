import Foundation
import VocabCore

extension StudyCalendar {
    /// A calendar with a fixed time zone, so tests don't depend on the one of the machine they run on.
    static let testing = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)
    /// `testing` after a switch to a time zone six hours behind, as when travelling.
    static let newYork = StudyCalendar(timeZone: TimeZone(identifier: "America/New_York")!, rolloverHour: 4)
}
