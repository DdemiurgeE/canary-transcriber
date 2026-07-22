# Testing and verification

Run from repository root:

```bash
swift test
swift build --product canary-transcriber
git diff --check
```

## Targeted suites

```bash
swift test --filter TranscriptionConfigurationTests
swift test --filter MeetingWorkspaceTests
swift test --filter TranscriptionEventTests
swift test --filter CaptureDiagnosticsTests
```

These suites cover configuration validation, output/meeting Markdown fallback, typed `CANARY_EVENT` parsing, and capture-file diagnostics without requiring live permissions or MLX models.

## Embedded Python syntax

The production runner is still embedded in `Sources/CanaryTranscriberLib/TranscriptionViewModel.swift` during the migration. Swift tests execute representative event fixtures. When changing the raw Python block, extract it and run:

```bash
python3 -m py_compile /tmp/canary-transcriber-runtime.py
```

Do not claim runtime transcription verification from a Swift build alone.

## Manual UI smoke test

1. Build and launch the app.
2. Confirm English labels, compact header, read-only Model text, and Profile-driven runtime/model values.
3. Add files through **Add files** and drag/drop; verify duplicate and directory handling.
4. Start a short transcription; verify per-file status, progress logs, **Stop**, **Clear logs**, and **Open output**.
5. Refresh ScreenCaptureKit apps and microphones. Verify icon-only recording buttons and delayed tooltips.
6. Record 5–10 seconds from a running app. With microphone enabled, verify non-tiny app-only `.m4a`, mic-only `.caf`, and mixed `.m4a`; verify mixed file enters queue.
7. If diarization is enabled, verify consent/model warnings are actionable and short audio falls back speakerless.

## Release checks

Installer and distribution checks are separate gates:

```bash
./scripts/build-canary-transcriber-app.sh
./scripts/build-installer-dmg.sh
codesign --verify --deep --verbose=2 "dist/Canary Transcriber.app"
```

Validate generated DMG/ZIP and SHA-256 files before publishing. Preserve unrelated dirty paths and stage only intended product changes.
