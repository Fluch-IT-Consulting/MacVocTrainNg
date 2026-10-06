# Issue-Tracker: GitHub

Issues und Specs liegen als GitHub-Issues in `Fluch-IT-Consulting/MacVocTrainNg`.
Alle Operationen laufen über die `gh`-CLI; sie leitet das Repo aus `git remote -v` ab.

## Befehle

- **Anlegen**: `gh issue create --type Bug|Feature|Task --label needs-triage --title "..." --body "..."`,
  mehrzeilige Rümpfe per Heredoc.
- **Lesen**: `gh issue view <nummer> --comments`
- **Auflisten**: `gh issue list --state open --json number,title,labels,assignees`
- **Kommentieren**: `gh issue comment <nummer> --body "..."`
- **Labels**: `gh issue edit <nummer> --add-label "..."` / `--remove-label "..."`
- **Schließen**: `gh issue close <nummer> --comment "..."`

## Typ und Label sagen Verschiedenes

Jedes Issue bekommt einen **Typ**. Er beschreibt, *was* das Issue ist:

| Typ | wofür |
|---|---|
| `Bug` | Verhalten, das so niemand wollte |
| `Feature` | eine neue Fähigkeit für den Benutzer |
| `Task` | Umbau ohne neue Fähigkeit: Nähte, Testbarkeit, Doppelungen, Doku, Werkzeuge |

Gesetzt wird er beim Anlegen (`--type`) oder nachträglich (`gh issue edit <n> --type Task`).

Die **Labels** tragen die Triage-Rolle, also wer als Nächstes dran ist, siehe
`triage-labels.md`. Die GitHub-Vorgaben `bug` und `enhancement` werden **nicht**
benutzt: Sie sagten dasselbe wie der Typ und widersprächen ihm bald.

Einzige Ausnahme ist die Herkunft: Jedes Issue aus einem Architektur-Review bekommt
zusätzlich `architektur-review`, und sein Rumpf endet mit
`Gefunden im Architektur-Review vom <Datum>.`

## Bevor die Arbeit an einem Issue beginnt

Erst nachsehen, ob schon jemand darauf sitzt:

```
gh issue view <nummer> --json assignees --jq '.assignees | map(.login)'
```

- **Niemand zugewiesen**: dem Menschen zuweisen, der die Arbeit anstößt
  (`gh issue edit <nummer> --add-assignee @me`).
- **Schon zugewiesen**: sagen, an wen, und nicht stillschweigend übernehmen.

## Ein Zweig je Issue

Der Typ bestimmt den **Zweignamen**: `bugfix/<nummer>` für einen `Bug`,
`feature/<nummer>` für ein `Feature`, `task/<nummer>` für einen `Task`. Gehören
mehrere kleine Issues zusammen, nennt der Zweig beide: `bugfix/12-13`.

Auf `main` wird nicht direkt committet. Jeder Zweig endet in einem Pull Request,
gemergt wird per **Rebase** (keine Merge-Commits), damit jeder Commit mit seinem
Titel auf `main` landet. Vor dem Pull Request müssen Build und alle Tests grün sein:

```
xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg test
```

## Der Commit-Titel nennt Typ und Issue

```
typ(#nummer): Ein Satz, der sagt, was der Commit tut
```

Beispiel: `fix(#14): Ein Tippfehler zählt nicht mehr als falsche Antwort`

Die Nummer gehört in die **Betreffzeile**: Die Commit-Liste auf GitHub zeigt nur
den Betreff, und in dieser Schreibweise wird die Nummer verlinkt.

| Typ | wofür |
|---|---|
| `feat` | eine neue Fähigkeit für den Benutzer |
| `fix` | Verhalten, das so niemand wollte |
| `refactor` | Umbau ohne Verhaltensänderung |
| `docs` | README, CLAUDE.md, diese Anleitungen |
| `test` | nur Tests, ohne Produktivcode |
| `style` | nur Formatierung, kein Zeichen mit Bedeutung geändert |
| `chore` | Werkzeug- und Ablagekram ohne Bezug zum Programm |
| `build`, `ci` | Xcode-Projekt, Package, Pipelines |

Zum **Issue-Typ**: `Bug` wird zu `fix`, `Feature` zu `feat`. Ein `Task` zerfällt in
das, was tatsächlich getan wurde, meist `refactor` oder `docs`.

Gehört ein Commit zu keinem Issue, entfällt der Geltungsbereich:
`docs: Das README nennt den Release-Befehl`.

Bricht eine Änderung bestehende **Stapeldateien** (`.voctrain`), trägt der Typ ein
Ausrufezeichen, dazu eine Fußzeile `BREAKING CHANGE: <was bricht>`. Das gilt auch,
wenn `DeckFile.currentVersion` steigt, die App ältere Dateien aber weiter liest:
Ältere App-Versionen können neue Dateien dann nicht mehr öffnen.

```
refactor(#4)!: Der Antwortverlauf liegt in einer eigenen Datei
```

## Commits und Issues verbinden

GitHub trägt einen Commit-Verweis erst in die Zeitleiste des Issues ein, wenn der
Commit `main` erreicht. Wer die Verbindung sofort sehen will, nennt das Issue im
Rumpf des Pull Requests.

Schlusszeile je Commit, direkt vor `Co-Authored-By`:

```
Teil von #<nummer>
```

Automatisch geschlossen wird nur, wo das Issue wirklich erledigt ist, im Rumpf des
Pull Requests:

```
Closes #<nummer>
```

Die Schlüsselwörter (`closes`, `fixes`, `resolves`) versteht GitHub nur auf Englisch.
Zwischenschritte eines Issues mit mehreren Pull Requests tragen kein Schlüsselwort,
sonst schließt der erste Merge das ganze Issue.

## Beziehungen zwischen Issues

| Beziehung | Bedeutung | Wie |
|---|---|---|
| Parent / Sub-Issue | Teil von, mit Fortschrittsanzeige am Elternteil | `gh issue edit <n> --parent <m>` |
| Blocked by / Blocking | echte Reihenfolge: erst das eine, dann das andere | `gh issue edit <n> --add-blocked-by <m>` |
| Relates to | gleichrangiger Bezug | nur von Hand in der Web-Oberfläche |

„Relates to“ ist weder über die API noch über `gh` erreichbar. Ein Agent schreibt den
Bezug deshalb in den Rumpf (die Erwähnung erzeugt beidseitig einen Querverweis), die
Beziehung selbst setzt ein Mensch nach.

Ein Sub-Issue ist die falsche Wahl, wenn das Elternteil vor dem Kind fertig wird.

## Keine persönlichen Daten in Issues

Das Repo ist privat, kann aber öffentlich werden, und die Issues mit ihm. Titel,
Rümpfe und Kommentare zeigen keine echten Vokabelsammlungen, Lernstände oder
Dateipfade des Benutzers. Beispiele mit erfundenen Wörtern; die Historie eines
Issues behält jeden Text, auch nach dem Bearbeiten.

## Pull Requests als Anfragekanal

**Nein.** Externe Pull Requests werden nicht als Feature-Wünsche behandelt.

## Wenn ein Skill sagt …

- „publish to the issue tracker“: ein GitHub-Issue anlegen.
- „fetch the relevant ticket“: `gh issue view <nummer> --comments`.
