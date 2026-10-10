# MacVocTrain NG

Vokabeltrainer für macOS, Neuentwicklung von MacVocTrain (2013–2016) in Swift und SwiftUI.

Du tippst deine Eingabe, die App prüft sie und schlägt eine Bewertung vor. Danach plant
[FSRS](https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm),
ein moderner Spaced-Repetition-Algorithmus, die nächste Abfrage: Karten kommen genau dann
wieder, wenn du sie sonst vergessen würdest.

## Funktionen

- **Stapel**: einer pro Datei (`.voctrain`), lesbares JSON, Autosave, Versionen
- **Kartenliste**: schnelles Erfassen (Frage ↩ Antwort ↩ Hinweis ↩), Bearbeiten in einem
  Blatt (Doppelklick auf die Karte, ↩ sichert), Suche (ignoriert Akzente: „dzien“ findet
  „dzień“), Inspektor mit Lernstand und Verlauf, Undo für alles
- **Lernen**: Eingabe tippen, ↩. Alternativen einer Antwort mit `/` trennen
  (`Haus / Gebäude`); wer nur einen Teil nennt, ist „unvollständig“, ein Tippfehler ergibt
  „fast richtig“ und wird markiert. Bewertung mit 1–4 (Nochmal/Schwer/Gut/Leicht), ⌘Z
  nimmt die letzte Abfrage zurück. Karten mit „Nochmal“ kommen in der Sitzung wieder, bis
  sie in der Wiederholungsphase sind; danach lassen sich die Fehler üben.
- **Statistik**: Fortschritt nach Reifegrad (Tag/Woche/Monat), Prognose der nächsten 30 Tage
- **Eigene FSRS-Parameter**: Ab 400 verwertbaren Abfragen berechnen die Lernoptionen die
  Parameter aus dem Verlauf des Stapels und vergleichen ihre Vorhersage mit den aktuellen
- **Import** von MacVocTrain-1-Dateien (`.mvt`) über *Ablage → MacVocTrain-1-Dokument
  importieren …*, inklusive Fortschritt
- **CSV und TSV**: *Ablage → Karten importieren …* hängt Karten (Frage, Antwort, optional
  Hinweis) an den offenen Stapel an; Trennzeichen und Kodierung werden erkannt, eine
  Vorschau markiert doppelte Fragen. *Ablage → Karten exportieren …* schreibt die Karten,
  wahlweise mit Reifegrad, Fälligkeit und Zahl der Abfragen
- Deutsch und Englisch (folgt der Systemsprache)

## Installation

Mit [Homebrew](https://brew.sh), macOS 14 oder neuer:

```bash
brew install --cask fluch-it-consulting/tap/macvoctrain
```

`brew upgrade` hält die App aktuell. Jede Version liegt außerdem als DMG unter
[Releases](https://github.com/Fluch-IT-Consulting/MacVocTrainNg/releases): öffnen und
MacVocTrain in den Ordner *Programme* ziehen.

Die App ist signiert, aber nicht notarisiert. Beim ersten Start blockiert macOS sie;
erlauben lässt sie sich einmal unter *Systemeinstellungen → Datenschutz & Sicherheit →
Dennoch öffnen*. Nach `brew upgrade` startet die neue Version ohne Rückfrage, eine neu
geladene DMG muss dagegen jedes Mal erlaubt werden.

## Projektstruktur

```
MacVocTrainNg/              Mac-App (SwiftUI): Ansichten, Zusammenführen über iCloud Drive
MacVocTrainNgTests/         Tests der App-Schicht (Undo, Lernablauf)
VocTrain/                   iPhone-App zum Lernen unterwegs, bearbeitet keine Karten
VocTrainTests/              Tests der iPhone-App
Shared/                     In beiden Apps: `VocabularyDocument`, Lokalisierung
Packages/VocabCore/         Plattformunabhängige Logik als Swift Package
  Model/                    Card, Deck, Dateiformat
  Scheduling/               FSRS-6, Scheduler (Lernschritte, Fälligkeit), Lerntage
  Optimization/             FSRS-Parameter aus dem Verlauf (Port von fsrs-rs)
  Check/                    Prüfung der Eingabe, Zeichen-Diff
  Session/                  Sitzung (Lernsitzung oder Üben), Abfragereihenfolge
  Statistics/               Reifegrad-Histogramme, Fortschritt, Prognose
  Import/                   Import von MacVocTrain 1
  Exchange/                 CSV/TSV lesen und schreiben, Karten aus Tabellenzeilen
  Search/                   Suche nach Karten, ohne Rücksicht auf Akzente
  Support/                  Kalenderdatum ohne Zeitzone, Zufallsgenerator mit Startwert
```

Die App-Schicht ist bewusst dünn; alles Fachliche steckt in `VocabCore` und ist ohne
UI testbar. Die iPhone-App nutzt das Paket und das Dokument aus `Shared/` mit.

## Bauen und testen

Voraussetzung: Xcode 26.3, dieselbe Version wie die CI; es läuft ab macOS 15.6. Die App
selbst läuft ab macOS 14.

- In Xcode: `MacVocTrainNg.xcodeproj` öffnen, ⌘R startet die App, ⌘U führt alle Tests aus.
  Das Schema `VocTrain` baut und testet die iPhone-App, im Simulator oder auf einem
  iPhone; dafür braucht es das Team in `Config/Signing.local.xcconfig` (siehe unten).
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

Ohne weitere Einrichtung signiert Xcode App und Tests ad hoc. Diese Signatur ändert
sich mit jedem Build, deshalb fragt macOS vor jedem Start, ob die neue Version auf die
Daten der vorigen zugreifen darf; die App-Tests starten die App jedes Mal. Abhilfe ist
ein Apple-Development-Zertifikat (Xcode → Settings → Accounts, ein kostenloses Personal
Team reicht) und daneben eine lokale, nicht eingecheckte `Config/Signing.local.xcconfig`:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <Team-ID>
```

Die Team-ID steht im Zertifikat (Schlüsselbundverwaltung, Feld „Organisationseinheit“).
Nach dem Wechsel fragt macOS ein letztes Mal.

Den Import mit einer echten alten Datei prüfen:

```bash
cd Packages/VocabCore && MVT_SAMPLE=~/Vokabeln/Beispiel.mvt swift test --filter importsRealDocument
```

Formatierung mit swift-format (liegt Xcode bei, Einstellungen in `.swift-format`);
`lint --strict` prüft, `format -i` statt `lint --strict` korrigiert:

```bash
xcrun swift-format lint --strict -r MacVocTrainNg MacVocTrainNgTests VocTrain VocTrainTests Shared Packages/VocabCore/Sources Packages/VocabCore/Tests Packages/VocabCore/Package.swift Tools
```

Ob jeder Text der App im String Catalog steht und jeder Schlüssel dort eine deutsche
Übersetzung hat, prüft nach einem Build mit `-derivedDataPath build/DerivedData`:

```bash
swift Tools/check-localizations.swift
```

Die CI (`.github/workflows/ci.yml`, macOS-Runner mit Xcode 26.3) läuft bei jedem Pull
Request und nach jedem Push auf `main`. Sie prüft swift-format, baut und testet mit
Warnungen als Fehlern, die iPhone-App im Simulator ebenso, prüft die Übersetzungen
wie oben und baut mit
`Tools/make-release.sh --build-only` die Release-Konfiguration für Apple Silicon und
Intel. Der Schalter baut nur, mit Warnungen als Fehlern, und hört vor dem Signieren und
dem Disk-Image auf. Sonst bleiben Warnungen lokal Warnungen.

Commits, die nur umformatieren, stehen in `.git-blame-ignore-revs`. GitHub blendet sie in
der Blame-Ansicht aus; damit `git blame` sie lokal auch überspringt, einmalig:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

Neue Swift-Dateien einfach in `MacVocTrainNg/` anlegen: Der Ordner ist mit dem Target
synchronisiert, die Projektdatei muss nicht angepasst werden.

## Weitergeben

```bash
Tools/make-release.sh
```

erzeugt `build/release/MacVocTrain-<Version>.dmg`: ein Universal Binary (Apple Silicon und
Intel) für macOS 14 oder neuer. Signiert wird mit dem Zertifikat aus
`Config/Signing.local.xcconfig`, ohne die Datei ad hoc. Empfänger müssen die App beim
ersten Start einmal erlauben (siehe Installation), ad hoc signiert nach jedem Update
erneut. Mit einer Developer ID (Apple Developer Program) signiert und notarisiert das
Skript die App, dann startet sie ohne Warnung. Die Variablen dafür stehen im Kopf des
Skripts.

Ein Release:

1. `MARKETING_VERSION` anheben und per Pull Request nach `main` bringen.
2. Auf dem aktuellen `main` hängt `Tools/make-release.sh --draft` die DMG an einen
   Release-Entwurf `v<Version>`. Ad hoc signiert es dafür nicht.
3. Den Entwurf auf GitHub prüfen und veröffentlichen. Das legt den Tag an, und der
   Workflow `tap-bump.yml` hebt die Cask im Tap
   [`fluch-it-consulting/tap`](https://github.com/Fluch-IT-Consulting/homebrew-tap) an.
   Scheitert er, lässt er sich unter *Actions* mit dem Tag von Hand nachholen. Er braucht
   einmalig einen Deploy Key, die Befehle stehen in seinem Kopf.

Die Signatur eines Releases ist öffentlich: `codesign -dvv` zeigt Apple-ID und Team-ID
des Zertifikats, mit dem es signiert ist.

## Lernalgorithmus

- **FSRS-6**; jeder Stapel beginnt mit den Standardparametern von open-spaced-repetition.
  Das Speichermodell ist gegen die Referenzwerte von py-fsrs getestet.
- Neue Karten und Karten nach einem Vergessen brauchen in der Sitzung *n* Lernschritte,
  also *n*-mal „Gut“ (einstellbar, Standard 2), bevor sie in die Wiederholungsphase kommen
  und einen Abstand in Lerntagen bekommen.
- Ein Lerntag beginnt um 4 Uhr; fällige Karten stehen den ganzen Lerntag zur Verfügung.
- Jede Abfrage wird mit Zeitpunkt und Bewertung im Verlauf der Karte gespeichert. Daraus
  berechnet ein Swift-Port des Optimierers von fsrs-rs 6.6.2 eigene FSRS-Parameter
  (ADR 0002); Tests vergleichen ihn mit fsrs-rs, die Vergleichswerte erzeugt
  `Tools/fsrs-reference`. Neue Parameter berechnen Stabilität und Schwierigkeit jeder
  Karte mit vollständigem Verlauf neu, Fälligkeiten bleiben.

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
Sichern nur, was sich seit dem letzten Mal geändert hat. Das Kodieren kostet deshalb
gleich viel, egal wie lang der Verlauf ist; Zusammenfügen und Schreiben von
`reviews.jsonl` wachsen mit ihm, bleiben aber billig. `progress` hält den Fortschritt,
einen Tagesstand je Lerntag: wie viele Karten neu waren und wie viele eine Stabilität
von unter 1, 1–2, 2–4, 4–8 … Tagen hatten. Fehlende Felder werden mit Standardwerten
ergänzt.

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

## Lizenz

MIT, siehe [`LICENSE`](LICENSE). Das FSRS-Modell ist aus
[py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) (MIT) portiert, der Optimierer
aus [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) (BSD 3-Clause); ihre
Lizenztexte stehen in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Die App zeigt alle
drei im Über-Fenster (`MacVocTrainNg/Resources/Credits.html`); wer dort Code von außen
ergänzt, trägt seine Lizenz in beiden Dateien nach.
