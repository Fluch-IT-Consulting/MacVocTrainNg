# Spike #246: Deck über iCloud Drive mit dem iPhone teilen

Wegwerfcode, wird nicht gemergt. Alles mit `SPIKE #246` markiert.

- `MacVocTrainNg/Spike/Spike246.swift`: Diagnose in der Mac-App. Ein zweiter
  `NSFilePresenter` auf dem offenen Paket loggt alle Callbacks, dazu den Zustand des
  `NSDocument` hinter dem `ReferenceFileDocument` und die Versionen des Pakets.
  Eingehängt in `DocumentView` (`.task(id: fileURL)`) und `VocabularyDocument.init(configuration:)`.
- `Spike/VocTrainPhone/`: minimale iPhone-App (eigenes Xcode-Projekt). `DocumentGroup`,
  liest mit `DeckFile.decode`, zeigt fällige Karten, bewertet die nächste über
  `SessionMode.study`, speichert zurück. Unten ein Ereignis-Log.
- `Spike/ExternalWriter/`: spielt „das andere Gerät“ (koordiniertes Schreiben wie iCloud).
  `swift run --package-path Spike/ExternalWriter writer append <deck>`; `post.swift`
  schickt der Mac-App `com.mfluch.spike246.dump` bzw. `.addCard`.

## Log der Mac-App

```
log stream --level debug --predicate 'subsystem == "com.mfluch.MacVocTrainNg" AND category == "spike246"'
```

Zustand aller offenen Decks ins Log schreiben:

```
swift Spike/ExternalWriter/post.swift com.mfluch.spike246.dump
```

## iPhone-App

1. Xcode › Settings › Components: iOS 18.2 installieren (fehlt auf diesem Mac).
2. `Spike/VocTrainPhone/VocTrainPhone.xcodeproj` öffnen. Signiert automatisch mit dem
   Team aus `Config/Signing.local.xcconfig`; ohne Team nur im Simulator.
3. iPhone (Entwicklermodus an) wählen, Run.

Ergebnisse: `Spike/FINDINGS-246.md`.
