# MacVocTrain NG

Vokabeltrainer für macOS, Neuentwicklung von MacVocTrain (2013–2016) in Swift und SwiftUI.

Du tippst deine Eingabe, die App prüft sie und schlägt eine Bewertung vor. Danach plant
[FSRS](https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm),
ein moderner Spaced-Repetition-Algorithmus, die nächste Abfrage: Karten kommen genau dann
wieder, wenn du sie sonst vergessen würdest.

## Funktionen

- **Stapel**: einer pro Datei (`.voctrain`), lesbares JSON, Autosave, Versionen
- **Kartenliste**: schnelles Erfassen (Frage ↩ Antwort ↩ Hinweis ↩), Suche (ignoriert
  Akzente: „dzien“ findet „dzień“), Inspektor mit Lernstand und Verlauf, Undo für alles
- **Lernen**: Eingabe tippen, ↩. Alternativen einer Antwort mit `/` trennen
  (`Haus / Gebäude`); wer nur einen Teil nennt, ist „unvollständig“, ein Tippfehler ergibt
  „fast richtig“ und wird markiert. Bewertung mit 1–4 (Nochmal/Schwer/Gut/Leicht), ⌘Z
  nimmt die letzte Abfrage zurück. Karten mit „Nochmal“ kommen in der Sitzung wieder, bis
  sie in der Wiederholungsphase sind; danach lassen sich die Fehler üben.
- **Statistik**: Fortschritt nach Reifegrad (Tag/Woche/Monat), Prognose der nächsten 30 Tage
- **Import** von MacVocTrain-1-Dateien (`.mvt`) über *Ablage → MacVocTrain-1-Dokument
  importieren …*, inklusive Fortschritt
- **CSV und TSV**: *Ablage → Karten importieren …* hängt Karten (Frage, Antwort, optional
  Hinweis) an den offenen Stapel an; Trennzeichen und Kodierung werden erkannt, eine
  Vorschau markiert doppelte Fragen. *Ablage → Karten exportieren …* schreibt die Karten,
  wahlweise mit Reifegrad, Fälligkeit und Zahl der Abfragen
- Deutsch und Englisch (folgt der Systemsprache)

## Projektstruktur

```
MacVocTrainNg/              App (SwiftUI): `VocabularyDocument`, Ansichten, Lokalisierung
MacVocTrainNgTests/         Tests der App-Schicht (Undo, Lernablauf)
Packages/VocabCore/         Plattformunabhängige Logik als Swift Package
  Model/                    Card, Deck, Dateiformat
  Scheduling/               FSRS-6, Scheduler (Lernschritte, Fälligkeit), Lerntage
  Check/                    Prüfung der Eingabe, Zeichen-Diff
  Session/                  Sitzung (Lernsitzung oder Üben), Abfragereihenfolge
  Statistics/               Reifegrad-Histogramme, Fortschritt, Prognose
  Import/                   Import von MacVocTrain 1
  Exchange/                 CSV/TSV lesen und schreiben, Karten aus Tabellenzeilen
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

## Weitergeben

```bash
Tools/make-release.sh
```

erzeugt `build/release/MacVocTrain-<Version>.dmg`: ein Universal Binary (Apple Silicon und
Intel) für macOS 14 oder neuer. Ohne Apple-Developer-Zertifikat ist die App nur ad hoc
signiert. Empfänger müssen sie beim ersten Start einmal erlauben: *Systemeinstellungen →
Datenschutz & Sicherheit → Dennoch öffnen*. Mit einer Developer ID (Apple Developer
Program) signiert und notarisiert das Skript die App, dann startet sie ohne Warnung.
Die Variablen dafür stehen im Kopf des Skripts.

## Lernalgorithmus

- **FSRS-6** mit den Standardparametern von open-spaced-repetition; das Speichermodell ist
  gegen die Referenzwerte von py-fsrs getestet.
- Neue Karten und Karten nach einem Vergessen brauchen in der Sitzung *n* Lernschritte,
  also *n*-mal „Gut“ (einstellbar, Standard 2), bevor sie in die Wiederholungsphase kommen
  und einen Abstand in Lerntagen bekommen.
- Ein Lerntag beginnt um 4 Uhr; fällige Karten stehen den ganzen Lerntag zur Verfügung.
- Jede Abfrage wird mit Zeitpunkt und Bewertung im Verlauf der Karte gespeichert, damit
  die FSRS-Parameter später an das eigene Gedächtnis angepasst werden können.

### Import aus MacVocTrain 1

Das alte Level-System wird so übersetzt, dass jede Karte genau dann fällig wird, wann
MacVocTrain 1 sie abgefragt hätte: Die FSRS-Stabilität entspricht dem alten Abstand des
Levels (0,7 Tage bei Level 1 bis 22 Tage bei Level 12, danach +3,52 Tage je Level).
Level 0 wird zu „Erneut lernen“, nie abgefragte Karten zu neuen Karten. Die Schwierigkeit
ist unbekannt und startet neutral bei 5. FSRS passt sie mit den ersten Abfragen an.

## Dateiformat

Ein Stapel ist ein Paket, also ein Ordner, den der Finder als eine Datei zeigt:

```
Stapel.voctrain/
  deck.json       Lernoptionen, Karten mit Lernstand, Fortschritt
  reviews.jsonl   Verlauf, eine Zeile je Abfrage
```

`deck.json`:

```json
{
  "format": "com.mfluch.voctrain.deck",
  "version": 3,
  "learningOptions": { "targetRecall": 0.9, "steps": 2, "cardsPerSession": 100, "…": "…" },
  "cards": [
    {
      "id": "…", "question": "der Gruß", "answer": "pozdrowienie", "hint": "…",
      "learningState": { "phase": "review", "stability": 12.3, "difficulty": 5.1, "due": "…", "reviews": 4, "…": "…" }
    }
  ],
  "progress": [ { "day": "2026-10-05", "bins": [0, 12, 40, "…"] } ]
}
```

`reviews.jsonl`, nach Karten gruppiert, `date` in Sekunden seit 1970, `grade` 1–4:

```
{"card":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":1791216000,"grade":3}
```

Der Verlauf liegt getrennt, weil er mit jeder Abfrage wächst: Die App kodiert beim
Sichern nur die neuen Zeilen, ein Autosave kostet deshalb gleich viel, egal wie lang
der Verlauf ist. `progress` hält den Fortschritt, einen Tagesstand je Lerntag: wie viele
Karten neu waren und wie viele eine Stabilität von unter 1, 1–2, 2–4, 4–8 … Tagen
hatten. Fehlende Felder werden mit Standardwerten ergänzt.

Die Schlüssel heißen wie die Begriffe im Glossar (`CONTEXT.md`). Die Versionen 1 (eine
einzelne JSON-Datei mit dem Verlauf in jeder Karte) und 2 (das Paket mit den Schlüsseln
von vor dem Glossar) stammen aus der Zeit vor der ersten Veröffentlichung; die App öffnet
sie nicht mehr.

## Entwicklungshilfen

Das App-Icon wird per Code gezeichnet. Nach Änderungen an `Tools/make-app-icon.swift`
neu erzeugen:

```bash
swift Tools/make-app-icon.swift
```

Im Debug-Build öffnet das Startargument `-debugScreen statistics|study|options` direkt
die jeweilige Ansicht (praktisch für Screenshots), `-debugSave YES` sichert alle
geöffneten Stapel kurz nach dem Öffnen (prüft den echten Speicherweg).
