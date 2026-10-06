import Testing
import VocabCore

struct DelimitedTextTests {
    @Test func plainFieldsStayUnquoted() {
        let text = DelimitedText.encode([["dom", "Haus", ""], ["kot", "Katze", "Tier"]], delimiter: .comma)
        #expect(text == "dom,Haus,\r\nkot,Katze,Tier\r\n")
    }

    @Test func quotesFieldsThatNeedIt() {
        let text = DelimitedText.encode([["a, b", "sagt \"ja\"", "zwei\nZeilen", "a;b"]], delimiter: .comma)
        #expect(text == "\"a, b\",\"sagt \"\"ja\"\"\",\"zwei\nZeilen\",a;b\r\n")
    }

    @Test func quotesOnlyForTheChosenDelimiter() {
        #expect(DelimitedText.encode([["a, b", "c\td"]], delimiter: .tab) == "a, b\t\"c\td\"\r\n")
        #expect(DelimitedText.encode([["a, b", "c;d"]], delimiter: .semicolon) == "a, b;\"c;d\"\r\n")
    }

    @Test func noRowsGiveEmptyText() {
        #expect(DelimitedText.encode([], delimiter: .comma) == "")
    }
}
