# MacVocTrain NG

macOS vocabulary trainer (SwiftUI, Swift 6, macOS 14+). The user writes German; code,
comments and base UI strings are English, German comes from the String Catalog.

## Commands

The active developer dir may be the Command Line Tools; prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if needed.

- Core tests: `cd Packages/VocabCore && swift test`
- App build + all tests: `xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg test`
- Lint: `xcrun swift-format lint --strict -r MacVocTrainNg MacVocTrainNgTests Packages/VocabCore/Sources Packages/VocabCore/Tests Packages/VocabCore/Package.swift Tools`
  (config in `.swift-format`); `format -i` instead of `lint --strict` fixes the layout.
  Name the paths: `build/` and `.build/` contain generated Swift files.
- Translations: `swift Tools/check-localizations.swift` after a build with
  `-derivedDataPath build/DerivedData`.
- CI: `.github/workflows/ci.yml`; its header comment lists what the job `test` checks.
- Signing: `Config/Signing.xcconfig` signs ad hoc; the untracked
  `Config/Signing.local.xcconfig` sets the team. No team ID in tracked files.

## Architecture

- `Packages/VocabCore`: all domain logic, no UI imports. Value types, `Sendable`.
  `Scheduler` applies a `Grade` to a `Card` (FSRS-6 in `FSRS.swift`, ported from py-fsrs);
  `SessionMode` runs a `StudySession` or a `Practice` and records reviews, each over
  a shared `Session` that only tracks card IDs and order.
- `MacVocTrainNg/Document/VocabularyDocument.swift`: `ReferenceFileDocument`. Every change
  must go through its `@MainActor` methods: they register undo, which is also how SwiftUI
  marks the document dirty. They register with the document's own `undoManager`, which
  `DocumentView` sets from its environment (tests set it themselves); callers don't pass
  one. Don't mutate `deck` elsewhere. Underneath, cards and learning
  options change only through `Deck.apply(_:at:calendar:)`: it returns the inverse change
  and keeps `progress` and `contentModified` in step. `VocabCore` builds each `DeckChange`; a card's learning state and
  log can't be set from outside it (tests reach the full `Card.init` via `@testable`).
- Reviews are undoable: the document applies the change `SessionMode.grade` returns and
  runs the restore of the `Session`, an opaque `UndoCompanion`, in the same undo action,
  after the card. The document knows no sessions.
- The Xcode project uses synchronized folders: new files in `MacVocTrainNg/` or
  `MacVocTrainNgTests/` are picked up automatically.

## Conventions

- New user-facing strings: add the German translation to
  `MacVocTrainNg/Resources/Localizable.xcstrings` (Xcode may not run to sync it), in
  state `translated`; a string whose wording depends on a count needs plural forms in
  both `en` and `de`. The CI fails on a key missing from the catalog or without German.
- Code ported from another project: add its license to `THIRD_PARTY_NOTICES.md` and
  `MacVocTrainNg/Resources/Credits.html` (the About window).
- Chart/status colours live in `Support/Presentation.swift`; the maturity ramp is a
  validated one-hue ordinal ramp, keep it that way.
- A deck is a package (`deck.json` + `reviews.jsonl`, see `DeckFile`); its keys are the
  glossary terms. Only the private records in `DeckFile` know its keys; domain types
  are not `Codable`. Versions 1 and 2 predate the first release and are no longer read.
  Missing keys decode with defaults, so newer app versions read older decks. Older app
  versions read newer decks of the same version too, but drop unknown keys and files
  on save. So a new field (in `deck.json` or `reviews.jsonl`) or file in the package
  comes without a bump of `DeckFile.currentVersion` only if losing it that way is
  acceptable; otherwise, and for incompatible changes, bump it: older app versions
  then reject the deck. The review log is encoded incrementally by `ReviewLogEncoder`:
  logs may only grow at the end or be replaced as a whole.

## Workflow

Every change goes through a GitHub issue, its own branch and a pull request; never
commit to `main` directly. Branch `bugfix/<n>`, `feature/<n>` or `task/<n>` after the
issue type; commit titles `typ(#n): Satz` (German), ending with `Teil von #n`; the PR
body closes the issue (`Closes #n`). Merge by rebase. Assign the issue before starting
and don't take over issues assigned to someone else.

Exception: a small change to code comments alone skips the issue. It still gets a branch
`task/<slug>` and a pull request; commit title `docs: Satz`, without `Teil von` or `Closes`.

### Issue tracker

GitHub issues in `Fluch-IT-Consulting/MacVocTrainNg`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Unattended agents

`Tools/agent-loop.sh` works through the `ready-for-agent` issues, one pull request each.
See `docs/agents/afk-loop.md`; the agent's prompt is `docs/agents/afk-prompt.md`.

### Triage labels

The five standard roles, label equals role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single context: `CONTEXT.md` and `docs/adr/` at the root, created when needed.
See `docs/agents/domain.md`.
