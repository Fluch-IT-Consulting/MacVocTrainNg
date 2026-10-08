# FSRS statt Level-System

MacVocTrain NG plant die Abfragen mit FSRS-6 statt mit den Leveln aus MacVocTrain 1.
Jede Karte hat einen Lernstand mit Stabilität und Schwierigkeit; ihr Abstand ist die Zahl
der Lerntage, bis ihre Abrufwahrscheinlichkeit auf die angestrebte Abrufquote fällt. Das
Speichermodell ist aus py-fsrs portiert, der Referenzimplementierung von
open-spaced-repetition.

## Erwogene Optionen

**Level beibehalten.** Ein Level gibt den nächsten Abstand fest vor: 0,7 Tage bei Level 1,
22 Tage bei Level 12, danach 3,52 Tage mehr je Level. Das ist leicht zu verstehen, und
Dokumente aus MacVocTrain 1 ließen sich ohne Übersetzung übernehmen. Dagegen spricht:

- Alle Karten auf einem Level bekommen bis auf eine Streuung von ±10 % denselben Abstand,
  egal wie schwer sie dem Lernenden fallen.
- Ab Level 12 wachsen die Abstände nur noch linear; über 100 Tagen liegt der Abstand erst
  ab Level 35. Karten, die längst sitzen, kommen dadurch sehr oft dran.
- Eine falsche Eingabe setzt jede Karte auf Level 0 zurück, auch eine, die der Lernende
  seit Monaten wusste.
- Level kennen keine Abrufwahrscheinlichkeit: Eine angestrebte Abrufquote lässt sich
  nicht einstellen, und ob eine Abfrage früh oder spät kam, ändert am nächsten Abstand
  nichts.

**SM-2, wie früher in Anki.** Jede Karte hat einen eigenen Faktor, mit dem ihr Abstand
wächst. Das behebt die ersten beiden Punkte. Dagegen spricht:

- Auch SM-2 kennt keine Abrufwahrscheinlichkeit und damit keine angestrebte Abrufquote.
- Der Faktor sinkt mit jedem Vergessen und jedem „Schwer“, steigt aber nur mit „Leicht“.
  Eine Karte, die einmal schwerfiel, kommt deshalb dauerhaft öfter dran, als sie müsste.
- Im Benchmark von open-spaced-repetition sagt FSRS die Abrufwahrscheinlichkeit deutlich
  genauer voraus als SM-2; Anki bietet FSRS seit Version 23.10 selbst an.

**FSRS-6 (gewählt).** FSRS schätzt für jede Karte Stabilität, Schwierigkeit und
Abrufwahrscheinlichkeit und lernt aus allen vier Bewertungen. Der Abstand folgt aus der
angestrebten Abrufquote, die der Lernende je Stapel einstellt. FSRS rechnet mit der Zeit,
die seit der letzten Abfrage tatsächlich vergangen ist, und ein Vergessen senkt die
Stabilität, ohne sie auf null zu setzen. Die 21 Gewichte des Modells lassen sich an das
Gedächtnis des Lernenden anpassen.

## Portiert aus py-fsrs

Übernommen ist nur das Speichermodell (`FSRS.swift`): wie Stabilität und Schwierigkeit
sich mit jeder Bewertung ändern, dazu die Standardgewichte. Das sind wenige Formeln; ein
Test vergleicht sie mit den Referenzwerten aus py-fsrs. Den Ablauf um das Modell herum,
also Phasen, Lernschritte und Fälligkeit, legt der `Scheduler` selbst fest, denn hier
weicht die App von py-fsrs ab: Ein Lernschritt ist ein „Gut“ in der Sitzung, keine
Wartezeit, und Abstände zählen in Lerntagen. Dafür genügt das Speichermodell, und
`VocabCore` braucht keine Abhängigkeit.

## Was die App dafür aufgibt

- **Durchschaubarkeit.** Am Level konnte der Lernende den nächsten Abstand ablesen.
  Stabilität und Schwierigkeit sind Schätzungen eines Modells; der Reifegrad fasst die
  Stabilität deshalb in wenige Stufen zusammen.
- **Die Bewertung durch die App.** MacVocTrain 1 entschied selbst, ob eine Eingabe gewusst
  war; der Lernende konnte eine falsche Eingabe nur noch gelten lassen. FSRS braucht eine
  von vier Bewertungen. Das Prüfergebnis schlägt sie vor, ob „Schwer“ oder „Gut“ passt,
  weiß aber nur der Lernende.
- **Einen einfachen Rückweg.** Lernstand und Fortschritt beruhen auf der Stabilität; die
  Tagesstände zählen Karten nach ihrer Stabilität. Ein anderes Verfahren müsste sie
  übersetzen, so wie der Import heute die Level.
- **Vorerst die eigenen Gewichte.** Die App rechnete zunächst nur mit den Standardgewichten
  von open-spaced-repetition. Der Verlauf hält jede Abfrage mit Zeitpunkt und Bewertung
  fest, damit sich die Gewichte später an den Lernenden anpassen lassen. Erledigt durch
  [ADR 0002](0002-optimierer-als-swift-port.md): Seitdem kann die App die Gewichte aus dem
  Verlauf eines Stapels berechnen; jeder Stapel beginnt mit den Standardgewichten.

## Import aus MacVocTrain 1

Der Import (`LegacyImporter`) übersetzt jedes Level so, dass die Karte genau dann fällig
wird, wann MacVocTrain 1 sie abgefragt hätte:

- Nie abgefragte Karten werden zu neuen Karten.
- Level 0 heißt „nicht gewusst“: Die Karte kommt in „Erneut lernen“ und ist sofort fällig,
  mit Stabilität und Schwierigkeit wie nach einem ersten „Nochmal“. Sie zählt eine Abfrage.
- Ab Level 1 kommt die Karte in die Wiederholungsphase. Ihre Stabilität ist der Abstand
  ihres Levels samt der Streuung von ±10 %, die MacVocTrain 1 je Karte gespeichert hat;
  fällig ist sie diesen Abstand nach ihrer letzten Abfrage. Die Schwierigkeit ist
  unbekannt und startet neutral bei 5. Das Level zählt als Zahl ihrer Abfragen.
- Die täglichen Zähler je Level werden zum Fortschritt: Jedes Level zählt im Tagesstand
  mit der Stabilität seines Abstands, ohne Streuung. Level 0 zählte in MacVocTrain 1 neue
  Karten und Karten nach einer falschen Eingabe zusammen; der Import teilt den Zähler
  deshalb geschätzt auf. Als neu zählen höchstens so viele Karten, wie beim Import nie
  abgefragt sind, der Rest als unsicher. Eine Karte, die beim Import nie abgefragt ist, war
  es an jedem früheren Tag auch, an dem es sie gab: Am letzten alten Tag stimmt die
  Aufteilung genau, sie macht am Importtag also keinen Sprung. An Tagen, bevor diese
  Karten angelegt wurden, zählen dafür Karten nach einer falschen Eingabe als neu.
- Den Tagesstand des Importtags bildet die App aus den Karten selbst. Karten ab Level 1
  zählen darin mit ihrer Streuung. Schiebt sie die Stabilität einer Karte über eine der
  Grenzen des Tagesstands (1, 2, 4, 8 … Tage), zählt die Karte am Importtag in einem
  anderen Bereich als am letzten alten Tag, an 4, 16, 64 und 256 Tagen auch mit einem
  anderen Reifegrad: Eine Karte auf Level 10 (15,5 Tage) mit +5 % zählt am letzten alten
  Tag als „Jung“, am Importtag als „Gefestigt“.

Die Stabilität ist die Zahl der Tage, bis die Abrufwahrscheinlichkeit auf 90 % fällt. Der
Import nimmt also an, dass der Lernende eine Karte zu ihrem Termin in MacVocTrain 1 noch
mit etwa 90 % wusste. Trifft das nicht zu, korrigieren die ersten Abfragen Stabilität und
Schwierigkeit.
