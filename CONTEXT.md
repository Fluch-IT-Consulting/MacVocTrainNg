# MacVocTrain NG

Ein Vokabeltrainer für den Mac. Der Lernende tippt zu einer Frage seine Eingabe, bewertet
sich selbst, und FSRS plant, wann er die Karte wiedersieht.

Stichwort ist der Begriff im Code, dahinter das deutsche Wort der Oberfläche. Beide gelten;
die Synonyme unter _Vermeiden_ nicht.

## Language

### Karten

**Card** (Karte):
Ein Paar aus Question und Answer, dazu ein optionaler Hint. Sie wird nur in eine Richtung
abgefragt, von der Question zur Answer.
_Vermeiden_: Vokabel, Eintrag, Karteikarte, Index card, Word, Entry

**Question** (Frage):
Die Seite einer Card, die gezeigt und abgefragt wird.
_Vermeiden_: Front, Vorderseite

**Answer** (Antwort):
Die erwartete Antwort einer Card; sie kann mehrere Alternatives enthalten.
_Vermeiden_: Back, Rückseite, Lösung; „Antwort“ für die Response oder die Review

**Alternatives** (Alternativen):
Mehrere gleichwertige Teile einer Answer, durch `/` getrennt. Ihre Reihenfolge ist egal;
wer nur einen Teil nennt, antwortet Incomplete. Besteht eine Answer oder Response nur aus
`/` und Leerraum, etwa `/`, ist sie als Ganzes eine einzige Alternative.
_Vermeiden_: Varianten, Synonyme

**Hint** (Hinweis):
Ein optionaler Zusatz, der zusammen mit der Question gezeigt wird.
_Vermeiden_: Remark, Bemerkung

**New card** (Neue Karte):
Eine Card, die noch nie in einer Study session abgefragt wurde.
_Vermeiden_: ungelernt, unseen

### Abfragen und Bewerten

**Review** (Abfrage):
Einmal eine Card abfragen und bewerten.
_Vermeiden_: Answer, Antwort, Wiederholung, Rep

**Response** (Eingabe):
Was der Lernende auf eine Question hin eintippt.
_Vermeiden_: Answer, „deine Antwort“

**Check result** (Prüfergebnis):
Wie die Response zur Answer passt: Correct, Incomplete, Almost correct oder Wrong. Es
schlägt eine Grade nur vor.
_Vermeiden_: Bewertung, Urteil

**Correct** (Richtig):
Die Response enthält alle Alternatives der Answer.
_Vermeiden_: „richtig“ für eine Grade, siehe Recalled

**Incomplete** (Unvollständig):
Die Response enthält nur einen Teil der Alternatives und nichts Falsches.

**Almost correct** (Fast richtig):
Die Response verfehlt die Answer nur um einen Tippfehler oder die Groß- und
Kleinschreibung.
_Vermeiden_: Typo, Tippfehler (als Ergebnis)

**Wrong** (Falsch):
Die Response ist weder Correct, Incomplete noch Almost correct, oder sie ist leer.
_Vermeiden_: „falsch“ für eine Grade, siehe Again

**Grade** (Bewertung):
Wie gut der Lernende eine Card wusste: Again, Hard, Good oder Easy. Die App schlägt eine
Grade vor, entscheiden tut der Lernende.
_Vermeiden_: Rating, Note, Score

**Again** (Nochmal):
Die Grade für eine Card, die der Lernende nicht wusste.
_Vermeiden_: failed, Wrong, falsch

**Recalled** (Gewusst):
Jede Grade außer Again.
_Vermeiden_: Correct, richtig

**Mistake** (Fehler):
Eine Card, die in einer Session mindestens einmal Again bekam.
_Vermeiden_: failed card, „falsch beantwortet“

**Lapse** (Vergessen):
Again für eine Card in der Review phase; sie fällt damit in Relearning.
_Vermeiden_: forgotten, „vergessene Karte“ als Begriff

### Lernstand

**Learning state** (Lernstand):
Was die App über das Gedächtnis des Lernenden zu einer Card weiß: Phase, Stability,
Difficulty, wann sie Due ist und wie viele Reviews und Lapses sie hatte. Eine New card hat
keinen. Zurücksetzen macht die Card wieder zur New card und leert ihr Review log.
_Vermeiden_: Memory state, Memory, Gedächtnis; Reset progress, Lernfortschritt zurücksetzen

**Phase** (Phase):
Wo eine Card im Lernen steht: Learning, Review phase oder Relearning. Eine New card hat
noch keine.

**Learning** (Lernend):
Die Phase einer Card nach ihrer ersten Review, bis sie genug Steps gesammelt hat.
_Vermeiden_: „Lernend“ als Maturity, siehe Shaky

**Review phase** (Wiederholungsphase):
Die Phase einer gelernten Card, die erst nach einem Interval wieder drankommt.
_Vermeiden_: Review (für die Phase), Wiederholung (ohne „-phase“), graduated

**Relearning** (Erneut lernen):
Die Phase einer Card nach einem Lapse, bis sie wieder genug Steps gesammelt hat.
_Vermeiden_: Neu lernen

**Step** (Lernschritt):
Eine Good für eine Card in Learning oder Relearning. Hard hält die Card auf ihrem Step,
Again setzt sie auf null zurück, Easy bringt sie sofort in die Review phase.
_Vermeiden_: Learning step als Zeitstufe (wie in Anki), „richtige Antwort“

**Stability** (Stabilität):
Die Zahl der Tage, bis die Recall probability einer Card auf 90 % fällt.

**Difficulty** (Schwierigkeit):
Wie schwer eine Card dem Lernenden fällt, von 1 bis 10.

**Recall probability** (Abrufwahrscheinlichkeit):
Die geschätzte Chance, eine Card jetzt zu wissen; in FSRS „retrievability“. Die Zeit seit
der letzten Review zählt in ganzen Study days, am Tag einer Review ist sie also 100 %.
_Vermeiden_: Retrievability, chance of remembering, Erinnerungswahrscheinlichkeit

**Target recall** (Angestrebte Abrufquote):
Die Recall probability, bei der eine Card in der Review phase wieder abgefragt wird; in FSRS
„desired retention“.
_Vermeiden_: Desired retention, Retention, Behaltensquote

**Parameters** (Parameter):
Die 21 Gewichte des FSRS-Modells, je Deck in den Learning options. Sie beginnen mit den
Standardwerten von open-spaced-repetition und lassen sich aus dem Review log des Decks
berechnen. Dafür zählen nur Reviews an einem späteren Study day als die vorige Review
derselben Card, und nur von Cards, deren Review log bis zur ersten Review reicht.

**Interval** (Abstand):
Die Zahl der Study days, bis eine Card in der Review phase wieder abgefragt wird.
_Vermeiden_: Wiederholungstermin, Pause

**Study day** (Lerntag):
Ein Tag, der um 4 Uhr morgens beginnt. Intervals zählen in Study days.
_Vermeiden_: Kalendertag, Tag

**Due** (Fällig):
Eine Card, die in der nächsten Study session drankommen kann: jede New card, jede Card in
Learning oder Relearning und jede Card, deren Interval abgelaufen ist.
_Vermeiden_: anstehend, offen

**Maturity** (Reifegrad):
Wie gut eine Card sitzt, nach ihrer Stability: New (Neu), Shaky (Unsicher, unter 4 Tagen
oder in Learning oder Relearning), Young (Jung, 4–16 Tage), Maturing (Gefestigt,
16–64 Tage), Mature (Sicher, 64–256 Tage), Mastered (Gemeistert, ab 256 Tagen).
_Vermeiden_: Status, Learning, Lernend

### Stapel

**Deck** (Stapel):
Eine Sammlung von Cards mit ihren Learning options und ihrem Progress, gespeichert in einer
Datei. Sein Name ist der Dateiname.
_Vermeiden_: Dokument, Datei, Kartei, Box, Index card box

**Learning options** (Lernoptionen):
Die Einstellungen, die für ein Deck gelten, etwa Target recall, die Zahl der Steps und die
Grenzen einer Session.
_Vermeiden_: Deck settings, Einstellungen

**Preferences** (Einstellungen):
Die Einstellungen der App, die für alle Decks gelten.
_Vermeiden_: Settings, Optionen

**Review log** (Verlauf):
Alle Reviews einer Card in einer Study session, jeweils mit Zeitpunkt und Grade.
_Vermeiden_: History, Antwortverlauf, Kartenverlauf

**Progress** (Fortschritt):
Wie sich die Cards eines Decks über die Zeit gefestigt haben, als Folge von Daily
snapshots.
_Vermeiden_: History, Verlauf, Statistikverlauf

**Daily snapshot** (Tagesstand):
Wie viele Cards eines Decks am Ende eines Study day wie stabil waren.
_Vermeiden_: Tagesstatistik

### Sitzungen

**Session** (Sitzung):
Reviews über eine feste Auswahl von Cards am Stück, bis alle erledigt sind oder der Lernende
aufhört. Es gibt Study sessions und Practice.
_Vermeiden_: Runde, Durchgang

**Study session** (Lernsitzung):
Eine Session über die Due Cards, deren Reviews den Learning state der Cards ändern. Eine Card
bleibt darin, bis sie in der Review phase ist. „Lernen“ ist das Verb dazu.
_Vermeiden_: Abfragerunde

**Practice** (Üben):
Eine Session über die Mistakes einer vorigen Session. Sie ändert keinen Learning state und
schreibt nichts ins Review log.
_Vermeiden_: Drill, Training, Fehlerrunde

### MacVocTrain 1

**MacVocTrain 1**:
Die Vorgänger-App; ihre Dokumente lassen sich als Deck importieren.

**Level**:
Die Stufe einer Karte in MacVocTrain 1, die ihren nächsten Abstand fest vorgab. Beim Import
wird daraus eine Stability. Nur im Zusammenhang mit dem Import benutzen.
