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
    }

    @Test func skipsHeaderAndIncompleteRows() {
        let result = candidates([["Question", "Answer"], ["dom", ""], ["nur eine Spalte"], ["", "Haus"], ["kot", "Katze"]], header: true)
        #expect(result.candidates.map(\.card.question) == ["kot"])
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
        let kot = CardImporter.Duplicate.inFile(question: "kot", answer: "Katze")
        #expect(result.candidates.map(\.duplicate) == [.inDeck, nil, kot, nil, kot])
    }

    /// Header, skipped and empty rows don't shift the reference to the earlier card (#188).
    @Test func duplicateInFileNamesTheEarlierCard() {
        let file = Data("Question;Answer\ndom;Haus\nmysz;\n\nkot;Katze\nKot;Kater\n".utf8)
        let rows = DelimitedText.decode(file).rows
        let result = CardImporter.candidates(from: rows, existing: [], isHeader: { $0 == ["Question", "Answer"] }, created: created)
        #expect(result.candidates.map(\.card.question) == ["dom", "kot", "Kot"])
        #expect(result.skippedRows == 1)
        #expect(result.candidates.map(\.duplicate) == [nil, nil, .inFile(question: "kot", answer: "Katze")])
    }
}
