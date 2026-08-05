# STEP 01 Output — Persistence State Plumbing

## Changes
- /Users/pavelpalnikov/Documents/Projects/personal/canary-transcriber/Sources/CanaryTranscriberCore/CanaryTranscriberCore.swift
  - Added `speakerAliasesStorageKey` as the shared persistence key.
  - Added `BatchConfig` and `parseSpeakerAliasesText(_:)` to a shared core module so they can be imported by both the app and the test target.
- /Users/pavelpalnikov/Documents/Projects/personal/canary-transcriber/Sources/CanaryTranscriberLib/CanaryTranscriber.swift
  - Switched the Speaker aliases editor to `@AppStorage(speakerAliasesStorageKey)`.
  - Kept the raw multiline alias text as the single source of truth for parsing and transcription config generation.
- /Users/pavelpalnikov/Documents/Projects/personal/canary-transcriber/README.md
  - Documented that speaker aliases are stored locally and restored on the next launch.
- /Users/pavelpalnikov/Documents/Projects/personal/canary-transcriber/Package.swift
  - Added a shared core target and separated the app wrapper from the reusable library code.

## Test Output
Command:
- `swift build --product canary-transcriber`

Result:
- Build of product 'canary-transcriber' complete! (0.18s)

## Notes
- Persistence uses the macOS app defaults domain via `@AppStorage`, which is sandbox-safe and low risk.
- The step’s plumbing is now isolated from the UI-heavy app target, which also makes the shared config/test path cleaner.

STATUS: DONE