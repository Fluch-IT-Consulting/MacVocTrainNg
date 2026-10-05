# MacVocTrain NG

Vokabeltrainer für macOS, Neuentwicklung von MacVocTrain (2013–2016) in Swift und SwiftUI.

Du tippst die Antwort, die App prüft sie und plant die nächste Abfrage mit
[FSRS](https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm),
einem modernen Spaced-Repetition-Algorithmus: Karten kommen genau dann wieder, wenn
du sie sonst vergessen würdest.

## Funktionen

- **Dokumente**: ein Stapel pro Datei (`.voctrain`), lesbares JSON, Autosave, Versionen
- **Kartenliste**: schnelles Erfassen (Frage ↩ Antwort ↩ Hinweis ↩), Suche (ignoriert
  Akzente: „dzien“ findet „dzień“), Inspektor mit Lernstand und Verlauf, Undo für alles
- **Lernen**: Antwort tippen, ↩. Mehrere richtige Antworten mit `/` trennen
  (`Haus / Gebäude`); teilweise Antworten zählen als „unvollständig“, Tippfehler werden
  erkannt und markiert. Bewertung mit 1–4 (Nochmal/Schwer/Gut/Leicht), ⌘Z nimmt die
  letzte Antwort zurück. Falsche Karten kommen in der Sitzung wieder, bis sie sitzen.
- **Statistik**: Verlauf nach Reifegrad (Tag/Woche/Monat), Prognose der nächsten 30 Tage
- **Import** von MacVocTrain-1-Dateien (`.mvt`) über *Ablage → MacVocTrain-1-Dokument
  importieren …*, inklusive Statistikverlauf
- Deutsch und Englisch (folgt der Systemsprache)

## Projektstruktur

```
MacVocTrainNg/              App (SwiftUI): Dokument, Ansichten, Lokalisierung
MacVocTrainNgTests/         Tests der App-Schicht (Undo, Lernablauf)
Packages/VocabCore/         Plattformunabhängige Logik als Swift Package
  Model/                    Card, Deck, Dateiformat
  Scheduling/               FSRS-6, Scheduler (Lernschritte, Fälligkeit), Lerntage
  Answer/                   Antwortprüfung, Zeichen-Diff
  Session/                  Lernsitzung und Abfragereihenfolge
  Statistics/               Reifegrad-Histogramme, Verlauf, Prognose
  Import/                   Import von MacVocTrain 1
```

Die App-Schicht ist bewusst dünn; alles Fachliche steckt in `VocabCore` und ist ohne
UI testbar. Eine iOS/iPadOS-App könnte das Paket direkt wiederverwenden.

## Bauen und testen

Voraussetzung: Xcode 16 oder neuer, macOS 14 oder neuer.

- In Xcode: `MacVocTrainNg.xcodeproj` öffnen, ⌘R startet die App, ⌘U führt alle Tests aus.
- Nur den Kern testen (schnell, ohne Xcode-Projekt):

```bash
cd Packages/VocabCore && swift test
```

Falls `swift test` oder `xcodebuild` meldet, dass nur die Command Line Tools aktiv
sind, entweder einmalig Xcode als Entwicklerverzeichnis setzen:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

oder pro Aufruf `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` voranstellen.

Den Import mit einer echten alten Datei prüfen:

```bash
cd Packages/VocabCore && MVT_SAMPLE=~/Private/polska.mvt swift test --filter importsRealDocument
```

Neue Swift-Dateien einfach in `MacVocTrainNg/` anlegen: Der Ordner ist mit dem Target
synchronisiert, die Projektdatei muss nicht angepasst werden.

## Lernalgorithmus

- **FSRS-6** mit den Standardparametern von open-spaced-repetition; das Speichermodell ist
  gegen die Referenzwerte von py-fsrs getestet.
- Neue und vergessene Karten müssen in der Sitzung *n*-mal richtig beantwortet werden
  (einstellbar, Standard 2), bevor sie einen Abstand in Tagen bekommen.
- Ein Lerntag beginnt um 4 Uhr; fällige Karten stehen den ganzen Tag zur Verfügung.
- Jede Antwort wird im Kartenverlauf gespeichert, damit die FSRS-Parameter später an das
  eigene Gedächtnis angepasst werden können.

### Import aus MacVocTrain 1

Das alte Level-System wird so übersetzt, dass jede Karte genau dann fällig wird, wann
MacVocTrain 1 sie abgefragt hätte: Die FSRS-Stabilität entspricht dem alten Abstand des
Levels (0,7 Tage bei Level 1 bis 22 Tage bei Level 12, danach +3,52 Tage je Level).
Level 0 wird zu „neu lernen“, nie beantwortete Karten zu neuen Karten. Die Schwierigkeit
ist unbekannt und startet neutral bei 5. FSRS passt sie mit den ersten Antworten an.

## Dateiformat

```json
{
  "format": "com.mfluch.voctrain.deck",
  "version": 1,
  "settings": { "desiredRetention": 0.9, "learningSteps": 2, "cardsPerSession": 100, "…": "…" },
  "cards": [
    {
      "id": "…", "question": "der Gruß", "answer": "pozdrowienie", "remark": "…",
      "memory": { "phase": "review", "stability": 12.3, "difficulty": 5.1, "due": "…", "…": "…" },
      "log": [ { "date": "2026-10-05T18:00:00Z", "grade": 3 } ]
    }
  ],
  "history": [ { "day": "2026-10-05", "bins": [0, 12, 40, "…"] } ]
}
```

`history` speichert pro Tag die Anzahl der Karten je Stabilitätsklasse
(neu, < 1 Tag, 1–2, 2–4, 4–8 … Tage). Unbekannte Felder älterer Versionen werden mit
Standardwerten ergänzt.

## Entwicklungshilfen

Im Debug-Build öffnet das Startargument `-debugScreen statistics|study|options` direkt
die jeweilige Ansicht (praktisch für Screenshots).
