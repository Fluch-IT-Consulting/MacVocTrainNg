// SPIKE #246: plays "another device" for an open deck. Usage: writer make|append [plain]|raw|count|versions <deck.voctrain>
import Foundation
import VocabCore

// Simulates another device: coordinated read + coordinated replace of a deck package.
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[2])
switch args[1] {
case "make":
    var deck = Deck()
    let cards = (1...5).map { Card(text: CardText(question: "q\($0)", answer: "a\($0)")!, created: Date()) }
    _ = deck.apply(DeckChange.adding(cards, to: deck)!, day: 0)
    try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
    print("made \(url.path)")
case "append":
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var error: NSError?
    coordinator.coordinate(writingItemAt: url, options: args.count > 3 && args[3] == "plain" ? [] : .forReplacing, error: &error) { writeURL in
        do {
            var deck = try DeckFile.decode(FileWrapper(url: writeURL))
            let card = Card(text: CardText(question: "external \(Date())", answer: "x")!, created: Date())
            _ = deck.apply(DeckChange.adding([card], to: deck)!, day: 0)
            try DeckFile.fileWrapper(for: deck).write(to: writeURL, options: .atomic, originalContentsURL: nil)
            print("appended, now \(deck.cards.count) cards")
        } catch { print("failed: \(error)") }
    }
    if let error { print("coordination error \(error)") }
case "raw":
    var deck = try DeckFile.decode(FileWrapper(url: url))
    let card = Card(text: CardText(question: "raw \(Date())", answer: "x")!, created: Date())
    _ = deck.apply(DeckChange.adding([card], to: deck)!, day: 0)
    try DeckFile.fileWrapper(for: deck).write(to: url, options: .atomic, originalContentsURL: nil)
    print("raw write, now \(deck.cards.count) cards")
case "versions":
    for v in NSFileVersion.otherVersionsOfItem(at: url) ?? [] {
        let deck = try DeckFile.decode(FileWrapper(url: v.url))
        print(v.modificationDate!, deck.cards.map(\.question).filter { !$0.hasPrefix("q") })
    }
    print("unresolved conflicts:", NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.count ?? -1)
case "count":
    let deck = try DeckFile.decode(FileWrapper(url: url))
    print("\(deck.cards.count) cards, \(deck.cards.reduce(0) { $0 + $1.log.count }) reviews")
default: break
}
