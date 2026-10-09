# Entwurf: Kommentar für #246

> Stand 2026-10-09. Fragen 1, 3 und 5 lokal beobachtet: Die Mac-App vom Zweig `task/246`
> hatte ein Deck offen, `Spike/ExternalWriter` hat das Paket koordiniert ersetzt, so wie
> iCloud Drive es beim Herunterladen tut. Noch offen und mit ⏳ markiert: was auf echtem
> iCloud Drive mit dem iPhone passiert (Fragen 2 und 4, Rest von 5).

## 1. Änderung von außen, Mac

Hinter `DocumentGroup` steht `SwiftUI.FileWrapperPlatformDocument` (→ `SwiftUI.PlatformDocument`
→ `NSDocument`), `autosavesInPlace` und `preservesVersions` sind an. Ein koordiniertes
Schreiben von außen kommt als `relinquishPresentedItem(toWriter:)`, dann `presentedItemDidChange`
und `presentedSubitemDidChange` für `deck.json` und `reviews.jsonl`.

- **a) ohne ungesicherte Änderungen:** Die App lädt still neu. Kein Dialog. NSDocument
  ruft `init(configuration:)` auf dem Hauptthread auf, SwiftUI gibt dem Fenster ein neues
  `VocabularyDocument`, `DocumentView` entsteht über `.id(ObjectIdentifier(file.document))`
  neu. Der Undo-Verlauf ist danach leer.
- **b) mitten in einer Study session:** Verhält sich wie a) oder c), je nachdem, ob der
  Autosave schon gelaufen ist. Weil `DocumentView` neu entsteht, ist die Sitzung ohne
  Meldung beendet, das Fenster zeigt wieder die Kartenliste. Bewertungen bis zum letzten
  Autosave stehen in der Datei. Der Autosave lief im Versuch 1 bis gut 2 s nach der Änderung.
- **c) mit ungesicherten Änderungen:** Die App lädt ebenfalls still neu, ohne Dialog, und
  überschreibt die fremde Fassung beim nächsten Autosave **nicht**. Die eigenen
  ungesicherten Änderungen legt NSDocument vorher als `NSFileVersion` ab
  (`presentedItemDidGain`, kein Konflikt). Erreichbar sind sie nur über
  Ablage › Zurücksetzen › Alle Versionen durchsuchen. Für den Lernenden verschwinden sie
  also still. Nachgeprüft: Die Version enthält genau die Karte, die vorher nur im Speicher war.
- Nebenbefund: Unkoordiniertes Schreiben (Terminal, `cp`) meldet der Presenter zwar
  (`presentedItemDidChange`), NSDocument lädt aber nicht neu. Für iCloud spielt das keine
  Rolle, iCloud schreibt koordiniert.
- ⏳ Auf echtem iCloud Drive bestätigen, dass sich a) und b) genauso verhalten.

## 2. Konflikt

⏳ Versuch auf iCloud Drive steht aus: Entstehen für das Paket Einträge in
`NSFileVersion.unresolvedConflictVersionsOfItem(at:)`, und was zeigt die Mac-App an?
Wichtig dafür: `usesUbiquitousStorage` ist `false`, weil die App kein iCloud-Entitlement
hat. NSDocument bietet dann keine eigene iCloud-Oberfläche. Ob es dennoch das
Konfliktfenster zeigt, ist offen.

## 3. Einhaken auf dem Mac

- `NSDocumentController.shared.document(for:)` liefert das NSDocument. Seine öffentliche
  API lässt sich nutzen (`isDocumentEdited`, `fileModificationDate`, `save`,
  `updateChangeCount`). Die Klasse gehört aber SwiftUI und ist privat: Ohne Swizzling lässt
  sich nicht ändern, dass sie neu lädt.
- Ein eigener `NSFilePresenter` auf dem Paket funktioniert in der Sandbox und bekommt alle
  Callbacks parallel zum NSDocument. Das Neuladen verhindern kann er nicht.
  Falle: Wer in einem Presenter-Callback das NSDocument fragt (`fileURL`, `document(for:)`),
  während ein anderer Prozess schreibt, verklemmt App und Schreiber. Also nur
  asynchron und danach.
- Folgerung: Nicht vor dem Neuladen mergen, sondern danach. Jedes neue Dokument (neu
  geöffnet oder neu geladen) prüft beim Erscheinen seine Konfliktfassungen. Die gerade
  angelegte Version mit eigenen ungesicherten Änderungen prüft es auch. Die Review logs
  daraus vereinigt es als `DeckChange` über die normalen Dokument-Methoden: Das ist
  rückgängig machbar, markiert das Dokument als geändert, und der Autosave schreibt das
  Ergebnis. Danach markiert es die Konflikte als gelöst. Weil das Vereinigen der Logs
  idempotent ist, schadet ein doppelter Merge nicht. Eine eigene `NSDocument`-Unterklasse
  (AppKit-Dokumente statt `DocumentGroup`) braucht es dafür nicht. Sie bliebe der
  Ausweg, falls das Neuladen selbst stört.
- Damit c) selten wird: nach jeder Bewertung sofort sichern statt auf den Autosave zu warten.

## 4. iOS

Spike-App unter `Spike/VocTrainPhone` (`DocumentGroup`, exportiertes `com.mfluch.voctrain.deck`
konform zu `.package`, `LSSupportsOpeningDocumentsInPlace`). Sie kompiliert für iOS 17.
Gebaut wurde sie hier nur per Typprüfung, weil die iOS-Plattform in Xcode fehlt.
⏳ Öffnet sie das Paket aus Dateien/iCloud Drive, liest und schreibt sie es, und wie
meldet sie Änderungen vom Mac und Konflikte?

## 5. Mac-Sandbox

`com.apple.security.files.user-selected.read-write` reicht lokal: Der eigene Presenter
bekommt alle Änderungen am geöffneten Paket. `NSFileVersion.otherVersionsOfItem(at:)` ist
lesbar und lässt sich mit `DeckFile.decode` lesen. ⏳ Für Konfliktfassungen auf iCloud
Drive noch zu bestätigen.

## Entscheidung

⏳ Erst nach den iCloud-Versuchen. Vorläufig sieht Variante A machbar aus, mit Merge nach
dem Neuladen wie unter 3 beschrieben. Kein Teil des Ablaufs überschreibt still eine fremde
Fassung. Die Gefahr ist umgekehrt: Eigene ungesicherte Mac-Änderungen verschwinden in einer
Version.
