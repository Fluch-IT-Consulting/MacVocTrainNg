# Das Dokument bleibt ObservableObject

`VocabularyDocument` ist ein `ObservableObject`, obwohl die View-Models und
`DueCardCounter` `@Observable` benutzen. Wer vom Deck hören will, nimmt einen von zwei
Kanälen: Views beobachten das Dokument mit `@ObservedObject` und bekommen
`objectWillChange` **vor** jeder Änderung. Alle anderen Beobachter, heute
`SessionViewModel` und `DueCardCounter`, hören auf `deckDidChange`, das **nach** jeder
Änderung sendet, wenn `deck` den neuen Stand hält. Die Regel steht in der Doku von
`VocabularyDocument` (#83).

## Erwogene Optionen

**Observation durchgängig.** Das Deck läge in einem `@Observable`-Modell, das das Dokument
besitzt. Views und View-Models beobachteten dieses Modell, Combine entfiele. Dagegen
spricht:

- Die zwei Zeitpunkte bleiben. SwiftUI braucht die Meldung vor der Änderung,
  `SessionViewModel` braucht den Stand danach: Es prüft, ob die Card, die gerade
  abgefragt wird, noch existiert. Das liegt an den Beobachtern, nicht am Mechanismus.
- Observation meldet bis macOS 14 nur vorher und nur einmal (`withObservationTracking`).
  Einen fortlaufenden Kanal nach der Änderung (`Observations`) gibt es erst ab macOS 26.
  Für die Beobachter außerhalb von Views bräuchte das Modell deshalb eine eigene Liste
  von Rückrufen, also ein nachgebautes `PassthroughSubject`. Es blieben zwei
  Mechanismen.
- `ReferenceFileDocument` verlangt `ObservableObject`. Das Dokument bliebe eines, nur
  ohne eigene Meldungen: eine Ebene mehr zwischen View und Deck.
- Feiner würde die Beobachtung nicht. Das Modell hätte eine einzige Eigenschaft `deck`;
  jede Änderung erreichte wie heute alle, die das Deck lesen.

**Zwei Kanäle im Dokument (gewählt).** Das Dokument meldet über `objectWillChange` und
`deckDidChange`; welcher Beobachter welchen nimmt, legt die Regel oben fest. Das kostet
das Nebeneinander von Combine und Observation, braucht aber keinen eigenen Mechanismus
und keine zusätzliche Ebene.

## Wann neu entscheiden

Wenn das Deployment-Ziel macOS 26 erreicht: Dann liefert `Observations` den Kanal nach
der Änderung, und ein `@Observable`-Modell käme ohne eigene Rückrufe aus. Bis dahin ist
ein Architektur-Review, das die zwei Kanäle bemängelt, auf dieses ADR zu verweisen.
