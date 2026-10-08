import Foundation
import Testing

struct LocalizationTests {
    /// The strings of `value` in the app's bundle for `language`, the way
    /// `CardImport.titles(for:)` loads them.
    private func localized(_ value: String.LocalizationValue, in language: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return String(localized: value, bundle: bundle, locale: Locale(identifier: language))
    }

    @Test func countsAreSingularForOne() throws {
        let file = "x.csv"
        let english: [(String.LocalizationValue, String)] = [
            ("Import \(1) Cards", "Import 1 Card"),
            ("Import \(2) Cards", "Import 2 Cards"),
            ("\(1) cards in “\(file)”", "1 card in “x.csv”"),
            ("\(2) cards in “\(file)”", "2 cards in “x.csv”"),
            ("\(1) rows without a question or an answer are left out.", "1 row without a question or an answer is left out."),
            ("\(2) rows without a question or an answer are left out.", "2 rows without a question or an answer are left out."),
            ("Export \(1) cards.", "Export 1 card."),
            ("Export \(2) cards.", "Export 2 cards."),
            ("Save the imported deck with \(1) cards.", "Save the imported deck with 1 card."),
            ("Save the imported deck with \(2) cards.", "Save the imported deck with 2 cards."),
            ("\(0) of \(1) cards", "0 of 1 card"),
            ("\(1) of \(2) cards", "1 of 2 cards"),
        ]
        let german: [(String.LocalizationValue, String)] = [
            ("Import \(1) Cards", "1 Karte importieren"),
            ("Import \(2) Cards", "2 Karten importieren"),
            ("\(1) cards in “\(file)”", "1 Karte in „x.csv“"),
            ("\(2) cards in “\(file)”", "2 Karten in „x.csv“"),
            ("\(1) rows without a question or an answer are left out.", "1 Zeile ohne Frage oder Antwort wird ausgelassen."),
            ("\(2) rows without a question or an answer are left out.", "2 Zeilen ohne Frage oder Antwort werden ausgelassen."),
            ("Export \(1) cards.", "1 Karte exportieren."),
            ("Export \(2) cards.", "2 Karten exportieren."),
            ("Save the imported deck with \(1) cards.", "Sichere den importierten Stapel mit 1 Karte."),
            ("Save the imported deck with \(2) cards.", "Sichere den importierten Stapel mit 2 Karten."),
            ("\(0) of \(1) cards", "0 von 1 Karte"),
            ("\(1) of \(2) cards", "1 von 2 Karten"),
        ]
        for (language, cases) in [("en", english), ("de", german)] {
            for (value, expected) in cases {
                let actual = try localized(value, in: language)
                #expect(actual == expected)
            }
        }
    }

    /// A text whose wording depends on a count has plural forms in every language.
    @Test func everyLanguageHasThePluralsOfTheOthers() throws {
        let languages = ["en", "de"]
        let pluralKeys = try languages.map { language in
            let url = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "stringsdict", subdirectory: nil, localization: language))
            let plurals = try #require(NSDictionary(contentsOf: url) as? [String: Any])
            return Set(plurals.keys)
        }
        #expect(!pluralKeys[0].isEmpty)
        #expect(pluralKeys[0] == pluralKeys[1])
    }
}
