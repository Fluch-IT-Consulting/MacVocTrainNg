import Foundation
import VocabCore

extension StudyCalendar {
    /// A calendar with a fixed time zone, so tests don't depend on the one of the machine they run on.
    static let testing = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!, rolloverHour: 4)
}
