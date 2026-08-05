# Project Agent Context

This file is automatically injected into every Hermes conversation in this project.

---

## Project Overview

Canary Transcriber is a native macOS SwiftUI app for batch audio/video transcription using local MLX speech-to-text models (Parakeet, Whisper, Canary v2, Voxtral), with optional pyannote speaker diarization and ScreenCaptureKit app-audio capture.

**Stack**: Swift 5.10, SwiftUI/AppKit, Swift Package Manager, XCTest, AVFoundation, ScreenCaptureKit, `ffmpeg`, embedded Python (`mlx-audio`/`mlx-whisper`/`canary-mlx`, `pyannote.audio`, HuggingFace Hub).
**Repo root**: `/Users/pavelpalnikov/Documents/Projects/personal/canary-transcriber`
**Test command**: `swift test`
**Lint command**: `swiftlint lint` (config: `.swiftlint.yml`)
**Run locally**: `swift run canary-transcriber`

---

## Service Vision

- **Core principle**: SwiftUI shell stays thin; transcription orchestration, configuration validation, process execution, output writing, and capture services live in testable Swift types under `CanaryTranscriberCore`/`CanaryTranscriberLib`, not in embedded Python or monolithic view files.
- **Approved tech additions**: `ffmpeg` subprocess, local Python venv for MLX/pyannote runtimes, ScreenCaptureKit/AVAudioEngine for capture.
- **Explicitly avoided**: bundling a Python runtime inside the app; cloud/remote transcription (local-only by design); persistent cross-file speaker identity claims.
- **Roadmap themes**: finish migrating the embedded Python Markdown/event-writing logic to the Swift core (`MeetingWorkspace.swift` already covers rendering); real notarized signing for distribution; auto-update.

---

## Directory Layout

```
canary-transcriber/
  Sources/CanaryTranscriberCore/   # pure Swift: config validation, chunk planning, diarization contracts, event parsing, Markdown/output rendering
  Sources/CanaryTranscriberLib/    # SwiftUI views, TranscriptionViewModel, capture services (ScreenCaptureKit/AVAudioEngine), ffmpeg mixing, embedded Python runtime
  Sources/CanaryTranscriberApp/    # executable entry point
  Tests/CanaryTranscriberTests/    # XCTest suite, mostly Core coverage
  scripts/                         # build-app, build-dmg, smoke-test-runtime, validate-release
  docs/                            # runtime-profiles.md, testing.md
  planning/                        # design docs (e.g. speaker-diarization-plan.md)
  pipeline/                        # Hermes pipeline stage artifacts (committed, not gitignored)
```

---

## Pipeline Artifacts

All pipeline artifacts live under `pipeline/<stage_id>/`:

| File pattern | Written by | Purpose |
|---|---|---|
| `STAGE_<id>.md` | Planner | Stage specification |
| `STAGE_<id>_REVIEW.md` | Reviewer | Review verdict |
| `STEPS_MANIFEST.md` | Decomposer | Ordered step list |
| `STEP_ID_<n>_<name>.md` | Decomposer | Step specification |
| `STEP_<n>_EXPLORE.md` | Explorer | Codebase map for step |
| `STEP_<n>_OUTPUT.md` | Implementer | Implementation result |
| `STEP_<n>_CHECK.md` | Critic | Validation verdict |
| `CTRL_*.md` | Controllers | Specialist reviews |
| `STAGE_<id>_ISSUES.md` | Orchestrator | Open issues log |
| `last_verified_commit` | Orchestrator | Last clean git SHA |

`pipeline/` is currently committed to the repo (not gitignored) — keep it that way unless a decision is made to stop tracking stage history.

---

## Coding Conventions

- Keep `CanaryTranscriberCore` free of SwiftUI/AppKit/Foundation-process imports — it must stay unit-testable without launching subprocesses.
- New process-launching code should go through the `ProcessRunning` protocol (`Sources/CanaryTranscriberCore/ProcessRunning.swift`) rather than calling `Process` directly, so it stays testable via dependency injection.
- All user-visible UI strings are English only; Russian is the default transcription *language*, not the UI language.
- Preserve `.canary.txt`/`.canary.json`/`.canary.md` output schemas — downstream tooling and tests depend on them.
- The embedded Python runtime in `TranscriptionViewModel.swift` and the Swift `MeetingWorkspace` renderer must stay behaviorally identical (same escaping/fallback rules) until the Python path is fully retired.

---

## Contacts / Escalation

Single-maintainer personal project — Pavel Palnikov (palnikov@anabion.com) makes all architecture, security, and release decisions.
