Migration / rollback review

Verdict: PASS — this change can be safely reverted.

Why:
- The edits are confined to `README.md` and `Sources/CanaryTranscriber/main.swift`; there is no database, on-disk schema, or package manifest migration to unwind.
- The new state added in `main.swift` is UI/runtime behavior only (extra model profiles, ScreenCaptureKit app-audio capture, microphone capture, speaker alias text storage).
- Persisted data impact is minimal and backward-compatible:
  - `@AppStorage("canary.speakerAliasesText")` stores a preference key in `UserDefaults`; reverting just leaves an unused preference behind.
  - Batch config JSON is written to a temporary file for the Python subprocess, so there is no long-term migration artifact to roll back.
  - Output/audio capture files are generated artifacts in Documents, not a shared app schema.
- `README.md` is documentation only and has no runtime effect.

Rollback notes:
- Reverting `main.swift` will remove the added profiles/capture workflow and return the app to the prior behavior.
- Any already-generated capture/transcription files will remain on disk, but they do not block rollback.

RESULT: PASS
