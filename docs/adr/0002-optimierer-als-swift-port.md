# Optimierer als Swift-Port von fsrs-rs

Die App berechnet die 21 Gewichte von FSRS-6 aus dem Verlauf eines Stapels selbst. Der
Optimierer ist aus fsrs-rs portiert, Version 6.6.2, dem letzten Release, das nur FSRS-6
kennt. Er liegt in `VocabCore/Optimization` und braucht wie das Speichermodell keine
Abhängigkeit.

## Erwogene Optionen

**fsrs-rs anbinden.** fsrs-rs ist der Optimierer, den auch Anki benutzt; die Gewichte
kämen genau aus der Referenz. Dagegen spricht:

- Das Crate hat keine C-Schnittstelle. Die eigenständigen C-Bindings (`fsrs-rs-c`)
  hängen an Version 5.2, Swift-Bindings gibt es keine. Die App bräuchte eine eigene
  C-Hülle samt Header.
- Der Build bräuchte eine Rust-Toolchain und eine Universal-Bibliothek für arm64 und
  x86_64, und `VocabCore` verlöre seine Abhängigkeitsfreiheit.
- `main` von fsrs-rs stellt gerade auf FSRS-7 um und ändert dabei auch die
  Hyperparameter von FSRS-6. Die App müsste eine Version festhalten und deren Pflege
  selbst übernehmen.

**Swift-Port (gewählt).** Seit Version 6 rechnet fsrs-rs die Gradienten von Hand aus
(`analytic.rs`) statt mit einem Framework für automatische Ableitung. Der Port braucht
deshalb nur Arithmetik: Lernbeispiele bilden, Ausreißer verwerfen, die Anfangsstabilitäten
vortrainieren, dann Adam mit Kosinus-Abkühlung, einem L2-Term zu den Startwerten und
festen Grenzen je Gewicht. Das sind einige hundert Zeilen. Die Mengen sind klein: Ein
Stapel mit einigen tausend Abfragen ist in Sekundenbruchteilen durchgerechnet.

## Treue zur Vorlage

Übernommen sind alle Hyperparameter von 6.6.2: 5 Epochen, Batches zu 512, Lernrate 0,04,
Adam mit β = (0,9; 0,999), höchstens 256 Abfragen je Beispiel, Gewichtung neuerer
Abfragen und die Grenzen je Gewicht. Abweichungen:

- **Doppelte statt einfacher Genauigkeit.** fsrs-rs rechnet den Vorwärtsdurchlauf in
  `f32`; der Port durchgehend in `Double`.
- **Ein eigener Zufallsgenerator.** fsrs-rs mischt die Reihenfolge der Batches mit
  `StdRng`, der Port mit `SeededRandom`. Bei mehr als 512 Beispielen weichen die Gewichte
  deshalb etwas ab. Ein Test vergleicht beide auf einem erfundenen Datensatz: mit einem
  einzigen Batch auf wenige Stellen genau, mit Batches zu 512 über die Güte der Vorhersage.
  `Tools/fsrs-reference` erzeugt die Vergleichswerte.
- **Lerntage statt Kalendertage.** Die Abstände der Lernbeispiele zählen in Lerntagen,
  wie überall in der App. fsrs-rs rechnet ebenfalls mit einem Tageswechsel, den der
  Aufrufer festlegt; Anki nimmt dafür wie die App 4 Uhr.
- **Lernschritte sind Abfragen am selben Tag.** Die Zahl der Lernschritte geht als
  `num_relearning_steps` in die Grenzen von w17 und w18 ein.

## Welche Abfragen zählen

Lernbeispiel ist jede Abfrage, die an einem späteren Lerntag als die vorige derselben
Karte stattfand, zusammen mit allen Abfragen davor. Abfragen am selben Tag gehen nur als
Vorgeschichte ein. Karten aus MacVocTrain 1 fehlt der Verlauf vor dem Import; sie zählen
nicht mit. Erkennbar ist ein vollständiger Verlauf daran, dass er so viele Einträge hat,
wie der Lernstand Abfragen zählt.

Die App bietet die Berechnung erst ab 400 Lernbeispielen an. fsrs-rs selbst trainiert ab
64 Beispielen, darunter passt es nur die Anfangsstabilitäten an; die Empfehlung von
open-spaced-repetition lautet aber einige hundert Abfragen.

## Was beim Übernehmen geschieht

Die App zeigt Log-Loss und RMSE der alten und der neuen Gewichte auf denselben
Lernbeispielen und übernimmt nur, wenn die neuen besser vorhersagen. Mit den neuen
Gewichten berechnet sie Stabilität und Schwierigkeit jeder Karte mit vollständigem
Verlauf aus diesem neu. Fälligkeiten bleiben, wie sie sind; die neuen Abstände gelten ab
der nächsten Abfrage. Dasselbe geschieht beim Zurücksetzen auf die Standardgewichte.
