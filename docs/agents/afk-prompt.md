Du setzt Issue #{{ISSUE}} in `Fluch-IT-Consulting/MacVocTrainNg` ohne Aufsicht um.
Niemand beantwortet Rückfragen. Was du nicht selbst entscheiden kannst, gibst du über
das Issue zurück (siehe unten), statt zu raten.

Dein Arbeitsverzeichnis ist ein eigener Worktree auf dem Zweig `{{BRANCH}}`, frisch
von `origin/main`. Das Issue ist schon zugewiesen. Arbeite nur in diesem Verzeichnis.

## Ablauf

1. Lies `CLAUDE.md`, `docs/agents/issue-tracker.md`, `docs/agents/domain.md` und das
   Issue samt Kommentaren: `gh issue view {{ISSUE}} --comments`.
2. Setz das Issue um. Ändert es Verhalten, schreib zuerst den Test, der ohne die
   Änderung fehlschlägt.
3. Vor dem ersten Commit muss alles grün sein:
   - `xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg -derivedDataPath build/DerivedData SWIFT_TREAT_WARNINGS_AS_ERRORS=YES test`
   - `swift Tools/check-localizations.swift` (liest, was der Build davor extrahiert hat)
   - `xcrun swift-format lint --strict -r MacVocTrainNg MacVocTrainNgTests Packages/VocabCore/Sources Packages/VocabCore/Tests Packages/VocabCore/Package.swift Tools`

   Zwischendurch reicht für VocabCore `swift test --package-path Packages/VocabCore`.
   Layout behebt `xcrun swift-format format -i` mit denselben Pfaden.
4. Commit nach `docs/agents/issue-tracker.md`: Titel `typ(#{{ISSUE}}): Satz` auf
   Deutsch, Schlusszeile `Teil von #{{ISSUE}}`, danach die Attributionszeilen, die
   Claude Code vorgibt. Ein Issue darf mehrere Commits haben, wenn jeder für sich
   einen Schritt macht.
5. `git push -u origin {{BRANCH}}`, dann `gh pr create --base main --head {{BRANCH}}`.
   Der Titel ist der Satz des Issues, der Rumpf sagt, was sich geändert hat und wie
   es geprüft wurde, und endet mit `Closes #{{ISSUE}}`.
6. Gib zum Schluss den Link zum Pull Request aus.

## Wenn du nicht weiterkommst

Gründe sind etwa: Die Spezifikation hat eine Lücke oder widerspricht dem Code, es
fehlt eine Entscheidung zum Aussehen oder zur Bedienung, die Tests werden nicht grün,
oder du bräuchtest ein Werkzeug außerhalb der Liste unten.

Dann legst du **keinen** Pull Request an und pushst nicht. Stattdessen:

1. Einen Kommentar ins Issue: was du versucht hast, woran es hängt, und konkrete
   Fragen, die ein Mensch beantworten kann.
2. `gh issue edit {{ISSUE}} --remove-label ready-for-agent --add-label <label>` mit
   - `needs-info`, wenn die Antwort auf deine Fragen reicht, damit ein Agent
     weitermachen kann,
   - `ready-for-human`, wenn ein Mensch selbst Hand anlegen muss.

Stößt du nebenbei auf einen anderen Fehler, legst du kein Issue an. Erwähne ihn im
Rumpf des Pull Requests oder im Kommentar.

## Werkzeuge

Verlassen kannst du dich nur auf Read, Glob, Grep, Edit, Write und Bash mit `git`,
`gh`, `xcodebuild`, `swift` und `xcrun`. Andere Befehle werden ohne Rückfrage
abgelehnt, bis auf einige, die nur lesen:

- Lesen und Suchen über Read, Glob und Grep, Dateien anlegen über Write, löschen und
  verschieben über `git rm` und `git mv`. Kein `cd`, `rm` oder `mkdir`.
- Keine verketteten Befehle (`&&`, `;`, `|`), kein `$(…)`, keine Heredocs. Längere
  Texte (Commit-Nachricht, PR-Rumpf, Kommentar) schreibst du mit Write nach
  `build/` (ist ignoriert) und übergibst sie mit `git commit -F`, `--body-file`.
- Nicht erlaubt sind außerdem: mergen, Issues anlegen oder schließen, `gh api`,
  force-push, push auf `main`.

## Eigenheiten dieses Repos

- `xcodebuild` sortiert manchmal `MacVocTrainNg.xcodeproj/project.pbxproj` um, ohne
  echte Änderung. Neue Dateien braucht das Projekt dort nicht (synchronisierte Ordner).
  Stell die Datei dann mit `git checkout origin/main -- MacVocTrainNg.xcodeproj/project.pbxproj`
  wieder her.
- Stage Dateien einzeln mit Namen, nie `git add -A` oder `git add .`.
- `MacVocTrainNg/Resources/Localizable.xcstrings` ist kompaktes JSON (zwei Leerzeichen
  Einrückung, Schlüssel sortiert). Neue Übersetzungen fügst du in diesem Format ein,
  ohne den Rest der Datei umzuformatieren.
- Die Zeilenlänge in `.swift-format` bleibt, wie sie ist. Zu lange Zeilen kürzt du
  von Hand.
- Issues, Kommentare und Pull Requests enthalten keine echten Vokabeln, Lernstände
  oder Dateipfade eines Benutzers, nur erfundene Beispiele.
