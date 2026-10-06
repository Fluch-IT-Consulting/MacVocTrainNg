import Foundation
import Testing
import VocabCore
@testable import MacVocTrain

@MainActor
struct CardExportTests {
    let calendar = StudyCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)

    private var studied: Card {
        var card = Card(question: "kot", answer: "Katze", hint: "Tier")
        let due = calendar.start(ofDay: CivilDate(year: 2026, month: 10, day: 9).dayNumber)
        card.learningState = LearningState(phase: .review, stability: 6, difficulty: 5, lastReview: due.addingTimeInterval(-6 * 86400), due: due, reviews: 4)
        return card
    }

    @Test func exportsQuestionAnswerAndHint() {
        let rows = CardExport.rows(of: [Card(question: "dom", answer: "Haus"), studied], includingLearningState: false, calendar: calendar)
        #expect(rows == [
            [String(localized: "Question"), String(localized: "Answer"), String(localized: "Hint")],
            ["dom", "Haus", ""],
            ["kot", "Katze", "Tier"],
        ])
    }

    @Test func learningStateAddsReadableColumns() {
        let rows = CardExport.rows(of: [Card(question: "dom", answer: "Haus"), studied], includingLearningState: true, calendar: calendar)
        #expect(rows[0].suffix(3) == [String(localized: "Maturity"), String(localized: "Due"), String(localized: "Reviews")])
        #expect(rows[1] == ["dom", "Haus", "", MaturityCategory.new.title, "", "0"])
        #expect(rows[2] == ["kot", "Katze", "Tier", MaturityCategory.young.title, "2026-10-09", "4"])
    }

    @Test func fileIsUTF8WithByteOrderMark() {
        let data = CardExport.data(of: [Card(question: "dzień", answer: "Tag")], format: .tsv, includingLearningState: false, calendar: calendar)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text.hasSuffix("\r\ndzień\tTag\t\r\n"))
    }
}
