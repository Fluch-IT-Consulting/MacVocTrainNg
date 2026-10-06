import Foundation
import Testing
import VocabCore

struct CardImporterTests {
    let created = Date(timeIntervalSince1970: 1_791_216_000)

    private func candidates(_ rows: [[String]], existing: [Card] = [], header: Bool = false) -> CardImporter.Result {
        CardImporter.candidates(from: rows, existing: existing, isHeader: { _ in header }, created: created)
    }

    @Test func readsQuestionAnswerAndHint() {
        let result = candidates([[" dom ", "Haus"], ["kot", "Katze", "Tier", "Jung", "2026-10-09", "4"]])
        #expect(result.candidates.map(\.card.question) == ["dom", "kot"])
        #expect(result.candidates.map(\.card.answer) == ["Haus", "Katze"])
        #expect(result.candidates.map(\.card.hint) == ["", "Tier"])
        #expect(result.candidates.allSatisfy { $0.card.isNew && $0.card.created == created })
        #expect(result.candidates.map(\.row) == [1, 2])
    }

    @Test func skipsHeaderAndIncompleteRows() {
        let result = candidates([["Question", "Answer"], ["dom", ""], ["nur eine Spalte"], ["", "Haus"], ["kot", "Katze"]], header: true)
        #expect(result.candidates.map(\.card.question) == ["kot"])
        #expect(result.candidates.map(\.row) == [5])
        #expect(result.skippedRows == 3)
    }

    @Test func onlyTheFirstRowCanBeAHeader() {
        let rows = [["dom", "Haus"], ["Question", "Answer"]]
        let result = CardImporter.candidates(from: rows, existing: [], isHeader: { $0 == ["Question", "Answer"] }, created: created)
        #expect(result.candidates.count == 2)
    }

    @Test func marksDuplicates() {
        let existing = [Card(question: "Dom ", answer: "Haus")]
        let result = candidates([["dom", "Heim"], ["kot", "Katze"], ["KOT", "Kater"], ["pies", "Hund"], ["Kot ", "Kocur"]], existing: existing)
        #expect(result.candidates.map(\.duplicate) == [.inDeck, nil, .inFile(row: 2), nil, .inFile(row: 2)])
    }
}
