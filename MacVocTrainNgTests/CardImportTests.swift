import Foundation
import Testing
import VocabCore

@testable import MacVocTrain

@MainActor
struct CardImportTests {
    let calendar = StudyCalendar.testing
    let created = Date(timeIntervalSince1970: 1_791_216_000)

    @Test func recognisesHeadersInEveryLanguage() {
        #expect(CardImport.isHeader(["Question", "Answer", "Hint"]))
        #expect(CardImport.isHeader([" question ", "ANSWER"]))
        #expect(CardImport.isHeader(["Frage", "Antwort", "Hinweis", "Reifegrad"]))
        #expect(!CardImport.isHeader(["dom", "Haus"]))
        #expect(!CardImport.isHeader(["Question"]))
    }

    @Test func readsAnExportBack() {
        let cards = [Card(question: "dom", answer: "Haus, Heim"), Card(question: "kot", answer: "Katze", hint: "Tier \"miau\"")]
        for format in CardExport.Format.allCases {
            let data = CardExport.data(of: cards, format: format, includingLearningState: true, calendar: calendar)
            let preview = CardImport.preview(of: data, fileName: "x", existing: [], created: created)
            #expect(preview.candidates.map(\.card.question) == ["dom", "kot"])
            #expect(preview.candidates.map(\.card.answer) == ["Haus, Heim", "Katze"])
            #expect(preview.candidates.map(\.card.hint) == ["", "Tier \"miau\""])
            #expect(preview.skippedRows == 0)
        }
    }

    @Test func duplicatesStartOutUnselected() {
        let data = Data("dom;Haus\nkot;Katze\nKot;Kater\npies;Hund\n".utf8)
        let preview = CardImport.preview(of: data, fileName: "x", existing: [Card(question: "dom", answer: "Heim")], created: created)
        #expect(preview.selectedCards.map(\.answer) == ["Katze", "Hund"])

        preview.selection = Set(preview.candidates.map(\.id))
        #expect(preview.selectedCards.map(\.answer) == ["Haus", "Katze", "Kater", "Hund"])
    }
}
