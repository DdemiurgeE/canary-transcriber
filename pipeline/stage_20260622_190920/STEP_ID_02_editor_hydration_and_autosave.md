## Goal
Hydrate the Speaker aliases editor from saved local storage on app launch and keep it synced as the user edits, so the text survives relaunches.

## Inputs
- Persistence plumbing from Step 01
- `ContentView` lifecycle in `Sources/CanaryTranscriber/main.swift`
- Existing `TextEditor(text: $speakerAliasesText)` binding

## Outputs
- Editor text loads from saved storage before the user starts a new transcription session
- Editor changes are written back to storage whenever the text changes
- Empty content remains empty after clearing and relaunching

## Hints
- Use an initialization or `.onAppear` path carefully to avoid overwriting in-progress edits or causing update loops.
- Do not alter the parser or the diarization config generation.
- Keep the existing TextEditor-based workflow intact; only add hydration/persistence around it.

## Test
- Launch the app, enter `SPEAKER_00 = Alice`, quit, and relaunch to confirm the text reappears.
- Clear the editor, close the app, and relaunch to confirm it stays empty.
- Verify the persisted text is still used in a transcription run.

## Complexity
Medium

## Parallelizable
No, it depends on the persistence mechanism established in Step 01 and touches the same SwiftUI state path.
