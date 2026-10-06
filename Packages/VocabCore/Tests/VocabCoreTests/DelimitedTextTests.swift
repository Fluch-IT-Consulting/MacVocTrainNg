import Foundation
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

struct DelimitedTextParsingTests {
    @Test func parsesQuotedFieldsAndAnyLineBreak() {
        let text = "dom,\"Haus, Heim\",\r\n\"sagt \"\"ja\"\"\",\"zwei\nZeilen\",x\rkot,Katze,Tier"
        #expect(DelimitedText.parse(text, delimiter: .comma) == [
            ["dom", "Haus, Heim", ""],
            ["sagt \"ja\"", "zwei\nZeilen", "x"],
            ["kot", "Katze", "Tier"],
        ])
    }

    @Test func skipsEmptyLinesButKeepsEmptyFields() {
        #expect(DelimitedText.parse("a;b\n\n;c\n", delimiter: .semicolon) == [["a", "b"], ["", "c"]])
    }

    @Test func isLenientWithStrayQuotes() {
        #expect(DelimitedText.parse("5\" Zoll,cal\n\"a\"b,c", delimiter: .comma) == [["5\" Zoll", "cal"], ["ab", "c"]])
    }

    @Test func roundTripsEncodedRows() {
        let rows = [["Frage", "Antwort", "Hinweis"], ["a, b", "\"c\"", "d\ne"], ["dzień", "Tag", ""]]
        for delimiter in DelimitedText.Delimiter.allCases {
            #expect(DelimitedText.parse(DelimitedText.encode(rows, delimiter: delimiter), delimiter: delimiter) == rows)
        }
    }

    @Test func detectsTheDelimiter() {
        #expect(DelimitedText.detectedDelimiter(in: "dom\tHaus, Heim\nkot\tKatze") == .tab)
        #expect(DelimitedText.detectedDelimiter(in: "dom;Haus, Heim\nkot;Katze, Kater\npies;Hund") == .semicolon)
        #expect(DelimitedText.detectedDelimiter(in: "dom,Haus\nkot,\"Katze; Kater\"\npies,Hund") == .comma)
        #expect(DelimitedText.detectedDelimiter(in: "dom,Haus,Gebäude\nkot,Katze,Tier") == .comma)
    }

    @Test func detectsTheEncoding() {
        let utf8 = Data("\u{FEFF}dzień;Tag\n".utf8)
        #expect(DelimitedText.decode(utf8).rows == [["dzień", "Tag"]])

        let latin1 = Data([0x54, 0xFC, 0x72, 0x3B, 0x64, 0x72, 0x7A, 0x77, 0x69, 0x0A]) // "Tür;drzwi" in Latin-1
        #expect(DelimitedText.decode(latin1).rows == [["Tür", "drzwi"]])

        let windows = Data([0x80, 0x09, 0x65, 0x75, 0x72, 0x6F]) // "€\teuro" in Windows-1252
        #expect(DelimitedText.decode(windows).rows == [["€", "euro"]])

        let utf16 = "dom\tHaus\n".data(using: .utf16)!
        #expect(DelimitedText.decode(utf16).rows == [["dom", "Haus"]])
        #expect(DelimitedText.decode(utf16).delimiter == .tab)
    }
}
