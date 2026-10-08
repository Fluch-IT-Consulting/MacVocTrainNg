# Issues ohne Aufsicht abarbeiten

`Tools/agent-loop.sh` arbeitet die offenen Issues mit `ready-for-agent` nacheinander ab.
Je Issue startet eine Claude-Code-Sitzung ohne Bildschirm (`claude -p`), die das Issue
umsetzt und einen Pull Request anlegt. Gemergt wird weiter von Hand.

Das Skript läuft auf dem Mac, nicht in einer Linux-Sandbox: Nur dort gibt es Xcode,
und ohne Build und Tests hätte der Agent keine Rückmeldung.

## Aufruf

```
Tools/agent-loop.sh              # alle freien Issues, das älteste zuerst
Tools/agent-loop.sh 197 189      # nur diese, ebenfalls das älteste zuerst
Tools/agent-loop.sh --dry-run    # nur zeigen, was laufen würde
```

Die Sitzungen laufen mit Opus 5.5 und 1M-Kontext (`claude-opus-5-5[1m]`) und Effort `high`.
`AGENT_MODEL` und `AGENT_EFFORT` überschreiben das für einen Aufruf, etwa
`AGENT_EFFORT=xhigh Tools/agent-loop.sh 177`. Ohne feste Werte würde ein Update von
Claude Code die Voreinstellungen unbemerkt ändern.

**Frei** ist ein Issue, wenn es offen ist, `ready-for-agent` trägt, nicht `blocked`
ist, keinen offenen Blocker hat, niemandem zugewiesen ist, einen Typ hat und es noch
keinen Zweig dafür gibt.

Am besten im Terminal starten, nicht aus einer Claude-Sitzung heraus: Die App-Tests
öffnen den Test-Host, und Rückfragen von macOS landen auf dem Bildschirm.

## Je Issue

1. Das Issue dem Aufrufer zuweisen.
2. Einen Worktree unter `.claude/worktrees/` auf `origin/main` anlegen, mit dem Zweig
   nach `issue-tracker.md`, und `Config/Signing.local.xcconfig` hineinkopieren.
3. `claude -p` im Worktree mit dem Prompt aus [`afk-prompt.md`](afk-prompt.md) starten,
   `{{ISSUE}}` und `{{BRANCH}}` ersetzt. Der Prompt kommt aus dem Checkout, in dem das
   Skript läuft. Wer ihn ändern will, kann ihn so vor dem Merge ausprobieren.
4. Die Ausgabe (`stream-json`) nach `.claude/agent-runs/<nummer>.log` schreiben.
5. Auswerten:

| Ergebnis | Erkennbar an | Danach |
|---|---|---|
| ✓ Pull Request | offener PR auf dem Zweig | Worktree und lokaler Zweig werden entfernt |
| ? zurückgegeben | `ready-for-agent` fehlt, dafür `needs-info` oder `ready-for-human` | Zuweisung wird aufgehoben, Worktree bleibt liegen |
| ✗ Fehler | weder noch | Zuweisung und Worktree bleiben, Log ansehen |

Endet `claude` mit einem Fehlercode (Anmeldung, Limit, Absturz), hört das Skript nach
diesem Issue auf, statt allen weiteren dasselbe anzutun.

Ein zurückgegebenes Issue wird wieder frei, sobald ein Mensch die Fragen beantwortet,
`ready-for-agent` zurückgesetzt und den alten Zweig gelöscht hat.

## Rechte

Ohne Aufsicht kann der Agent nicht um Erlaubnis fragen. Er läuft mit
`--permission-mode dontAsk` und einer Positivliste: Read, Glob, Grep, Edit, Write,
TodoWrite und Bash mit `git`, `gh`, `xcodebuild`, `swift` und `xcrun`. Alles andere wird
ohne Rückfrage abgelehnt, bis auf Befehle, die Claude Code selbst als nur lesend
einstuft (etwa `ls`). Ausdrücklich verboten sind zusätzlich mergen, Issues anlegen,
schließen oder löschen, `gh api`, `gh repo`, force-push und push auf `main`.

Die Liste ist eine Leitplanke, keine Sandbox: `git` und `gh` können viel, und ein
Agent mit Schreibrecht auf das Repo kann Schaden anrichten. Deshalb mergt ein Mensch.

Die Liste steht im Skript (`ALLOWED_TOOLS`, `DISALLOWED_TOOLS`), der Prompt erklärt
dem Agenten, wie er damit auskommt.
