# Fachdokumentation

Wie die Skills die Fachdokumentation dieses Repos lesen.

## Vor dem Erkunden lesen

- **`CONTEXT.md`** in der Wurzel: das Glossar
- **`docs/adr/`**: die Entscheidungen, die den Bereich betreffen, an dem gearbeitet wird

Fehlen diese Dateien, **ohne Hinweis weitermachen**. Nicht vorschlagen, sie vorab
anzulegen: Der Skill `/domain-modeling` legt sie an, sobald ein Begriff oder eine
Entscheidung tatsächlich geklärt wird.

## Aufbau

Ein Kontext, also ein Glossar und ein ADR-Ordner in der Wurzel:

```
/
├── CONTEXT.md
├── docs/adr/
│   └── 0001-fsrs-statt-level-system.md
├── MacVocTrainNg/
└── Packages/VocabCore/
```

## Das Vokabular des Glossars benutzen

Wo ein Ergebnis einen Fachbegriff nennt (Issue-Titel, Umbauvorschlag, Testname),
gilt der Begriff aus `CONTEXT.md`. Bis es das Glossar gibt, gelten die Namen im Code:
`Card`, `Deck`, `Grade`, `MemoryState`, `StudySession`, `MaturityCategory`.

## Widersprüche zu einem ADR offen nennen

Widerspricht ein Ergebnis einem bestehenden ADR, das ausdrücklich sagen statt es still
zu übergehen:

> _Widerspricht ADR-0003 (…), aber es lohnt sich, das neu aufzurollen, weil …_
