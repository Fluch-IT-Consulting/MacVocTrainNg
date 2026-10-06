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

## Architecture

- `Packages/VocabCore`: all domain logic, no UI imports. Value types, `Sendable`.
  `Scheduler` applies a `Grade` to a `Card` (FSRS-6 in `FSRS.swift`, ported from py-fsrs);
  `Session` only tracks card IDs and order.
- `MacVocTrainNg/Document/VocabularyDocument.swift`: `ReferenceFileDocument`. Every change
  must go through its `@MainActor` methods: they register undo, which is also how SwiftUI
  marks the document dirty. Don't mutate `deck` elsewhere.
- Reviews are undoable; `UndoHook` restores the `Session` alongside the card.
- The Xcode project uses synchronized folders: new files in `MacVocTrainNg/` or
  `MacVocTrainNgTests/` are picked up automatically.

## Conventions

- New user-facing strings: add the German translation to
  `MacVocTrainNg/Resources/Localizable.xcstrings` (Xcode may not run to sync it).
- Chart/status colours live in `Support/Presentation.swift`; the maturity ramp is a
  validated one-hue ordinal ramp, keep it that way.
- A deck is a package (`deck.json` + `reviews.jsonl`, see `DeckFile`); its keys are the
  glossary terms. Versions 1 and 2 predate the first release and are no longer read.
  Bump `DeckFile.currentVersion` only for incompatible changes; new optional fields
  decode with defaults. The review log is encoded incrementally by `ReviewLogEncoder`:
  logs may only grow at the end or be replaced as a whole.

## Workflow

Every change goes through a GitHub issue, its own branch and a pull request; never
commit to `main` directly. Branch `bugfix/<n>`, `feature/<n>` or `task/<n>` after the
issue type; commit titles `typ(#n): Satz` (German), ending with `Teil von #n`; the PR
body closes the issue (`Closes #n`). Merge by rebase. Assign the issue before starting
and don't take over issues assigned to someone else.

### Issue tracker

GitHub issues in `Fluch-IT-Consulting/MacVocTrainNg`, via the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five standard roles, label equals role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single context: `CONTEXT.md` and `docs/adr/` at the root, created when needed.
See `docs/agents/domain.md`.
