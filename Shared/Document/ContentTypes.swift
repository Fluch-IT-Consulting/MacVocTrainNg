import UniformTypeIdentifiers

extension UTType {
    /// Decks of this app: packages with the extension `.voctrain` (see `DeckFile`).
    /// Single JSON files of format version 1 carry the same type.
    static let vocabularyDeck = UTType(exportedAs: "com.mfluch.voctrain.deck", conformingTo: .package)
    /// Documents of MacVocTrain 1 (`.mvt`), which can be imported.
    static let legacyMacVocTrain = UTType(importedAs: "com.mfluch.MacVocTrain", conformingTo: .data)
}
