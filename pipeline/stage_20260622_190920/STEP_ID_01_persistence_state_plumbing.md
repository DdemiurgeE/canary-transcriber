## Goal
Add a lightweight local persistence layer for the Speaker aliases editor text using macOS app storage (`@AppStorage` or `UserDefaults`) without changing alias parsing or transcription behavior.

## Inputs
- `Sources/CanaryTranscriber/main.swift`
- Current `speakerAliasesText` state and `parsedSpeakerAliases()` logic
- Stage constraints favoring sandbox-safe local storage

## Outputs
- A stable persistence key for the raw alias editor text
- Helper logic or property wiring to read/write the editor string from local app storage
- No changes to the visible UI or alias format

## Hints
- Keep persistence focused on the raw multiline editor contents, not the parsed alias map.
- Prefer the smallest change that preserves the current manual workflow.
- Use a single source of truth to avoid introducing duplicated state.

## Test
- Build the app after the state/storage change.
- Confirm the project still compiles with no SwiftUI state errors.

## Complexity
Low

## Parallelizable
Yes, once the storage approach and key are chosen, UI wiring can be implemented separately.
