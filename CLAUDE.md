# MacVocTrain NG

macOS vocabulary trainer (SwiftUI, Swift 6, macOS 14+). The user writes German; code,
comments and base UI strings are English, German comes from the String Catalog.

## Commands

The active developer dir may be the Command Line Tools; prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if needed.

- Core tests: `cd Packages/VocabCore && swift test`
- App build + all tests: `xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg test`

## Architecture

- `Packages/VocabCore`: all domain logic, no UI imports. Value types, `Sendable`.
  `Scheduler` applies a `Grade` to a `Card` (FSRS-6 in `FSRS.swift`, ported from py-fsrs);
  `StudySession` only tracks card IDs and order.
- `MacVocTrainNg/Document/VocabularyDocument.swift`: `ReferenceFileDocument`. Every change
  must go through its `@MainActor` methods: they register undo, which is also how SwiftUI
  marks the document dirty. Don't mutate `deck` elsewhere.
- Study answers are undoable; `UndoHook` restores the `StudySession` alongside the card.
- The Xcode project uses synchronized folders: new files in `MacVocTrainNg/` or
  `MacVocTrainNgTests/` are picked up automatically.

## Conventions

- New user-facing strings: add the German translation to
  `MacVocTrainNg/Resources/Localizable.xcstrings` (Xcode may not run to sync it).
- Chart/status colours live in `Support/Presentation.swift`; the maturity ramp is a
  validated one-hue ordinal ramp, keep it that way.
- File format changes: bump `DeckFile.currentVersion` only for incompatible changes; new
  optional fields decode with defaults.
