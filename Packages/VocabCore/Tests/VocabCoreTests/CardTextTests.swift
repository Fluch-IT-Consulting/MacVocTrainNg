import Testing
import VocabCore

struct CardTextTests {
    @Test func trimsSurroundingWhitespace() throws {
        let text = try #require(CardText(question: "  dobry  dzień\n", answer: "\tguten  Tag ", hint: " Gruß\n"))
        #expect(text.question == "dobry  dzień")
        #expect(text.answer == "guten  Tag")
        #expect(text.hint == "Gruß")
    }

    @Test func requiresQuestionAndAnswer() {
        #expect(CardText(question: " \n", answer: "Haus") == nil)
        #expect(CardText(question: "dom", answer: "\t") == nil)
        #expect(CardText(question: "", answer: "") == nil)
    }

    @Test func hintMayBeEmpty() {
        #expect(CardText(question: "dom", answer: "Haus", hint: "  ")?.hint == "")
    }

    @Test(arguments: [
        ("Dom", " dom\n"),
        ("Straße", "STRASSE"),
        ("Ärger", "ärger"),
        ("ﬁsh", "FISH"),
        ("ΣΟΦΟΣ", "σοφος"),
        ("İstanbul", "i\u{307}stanbul"),
        ("CAF\u{C9}", "cafe\u{301}"),
    ])
    func questionsDifferingInCaseAreTheSame(_ question: String, _ other: String) {
        #expect(CardText.key(forQuestion: question) == CardText.key(forQuestion: other))
    }

    @Test(arguments: [
        ("dom", "dóm"),
        ("Ärger", "Arger"),
        ("İstanbul", "istanbul"),
        ("ISTANBUL", "ıstanbul"),
        ("dom", "do m"),
    ])
    func questionsDifferingOtherwiseAreNotTheSame(_ question: String, _ other: String) {
        #expect(CardText.key(forQuestion: question) != CardText.key(forQuestion: other))
    }
}
