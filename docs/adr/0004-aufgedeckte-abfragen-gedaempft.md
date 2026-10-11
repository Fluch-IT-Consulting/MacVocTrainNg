# Aufgedeckte Abfragen bringen ein Drittel des Stabilitätsgewinns

Auf dem Mac tippt der Lernende die Antwort, auf dem iPhone deckt er sie auf und bewertet
sich selbst. Beide Abfragen landen im selben Verlauf. FSRS kennt nur die Bewertung, nicht
die Abfrageart, und rechnet jedes „Gut“ gleich. Aufdecken prägt aber weniger ein als
Tippen, und nach dem Aufdecken bewertet man sich eher zu gut. Nach aufgedeckten Abfragen
würden die Abstände deshalb zu lang; erst ein späteres Vergessen auf dem Mac korrigierte
das (#268).

## Entscheidung

Eine aufgedeckte Abfrage, bei der die Karte gewusst wird (Schwer, Gut, Leicht), behält ein
Drittel der Stabilität, die FSRS hinzurechnet: `S' = S + (S_FSRS − S) / 3`. Sinkt die
Stabilität, gilt der Wert von FSRS. „Nochmal“ zählt voll: Wer die Antwort nicht wusste,
wusste sie nicht. Schwierigkeit und Anfangsstabilität rechnet FSRS unverändert.

Der Anteil ist `ReviewMode.stabilityGainShare`. Er gilt beim Bewerten, beim Nachrechnen
aus dem Verlauf (Zusammenführen, neue Gewichte) und im Optimierer. Der Optimierer nimmt
aufgedeckte Abfragen nicht als Lernbeispiel, weil ihre Bewertung zu optimistisch ist; in
der Vorgeschichte späterer Beispiele zählen sie gedämpft.

Das Drittel ist gesetzt, nicht gemessen. Der Verlauf speichert die Abfrageart, sodass sich
der Anteil später an den eigenen Daten prüfen lässt.

## Erwogene Optionen

- **Nichts ändern.** FSRS korrigiert sich über spätere Fehler, aber nur um den Preis von
  mehr Vergessen.
- **Aufgedeckte Abfragen ändern die Planung nicht**, wie die Übung der Fehler auf dem Mac.
  Dann zählte das Lernen unterwegs gar nicht.
- **„Gut“ als „Schwer“ werten.** Einfach, aber „Schwer“ erhöht dauerhaft die
  Schwierigkeit der Karte.
- **Auch auf dem iPhone tippen.** Widerspricht dem Zweck der iPhone-App, schnell
  zwischendurch zu lernen.

## Folgen

Kein neues Dateiformat: Die Abfrageart steht schon in `reviews.jsonl`. Bestehende Karten
übernehmen die Dämpfung, sobald ihr Verlauf nachgerechnet wird. Ältere App-Versionen
rechnen ohne Dämpfung; führt ein Gerät mit älterer Version zusammen, gilt dessen Ergebnis,
bis eine neuere Version den Verlauf wieder nachrechnet.
