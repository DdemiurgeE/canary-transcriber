# Architecture / SRE Review

## Scope
Reviewed the changed files:
- `README.md`
- `Sources/CanaryTranscriber/main.swift`

## Summary
The implementation is workable for a small local macOS utility and has some good operational guardrails, but it is still very monolithic. The main risk is maintainability and testability rather than an immediate production outage risk.

## What looks good
- Clear runtime checks for missing `python`, `ffmpeg`, and missing audio files before batch execution.
- Explicit lifecycle handling for capture and transcription processes, including cleanup of temp config files and termination handling.
- Good local observability for a desktop app:
  - live UI log panel
  - persistent log file under `~/Documents/CanaryTranscripts/canary-transcriber.log`
  - structured `CANARY_EVENT` lines emitted by the embedded Python runner and parsed back into UI status updates
- The app already surfaces permission guidance and runtime failures in the UI, which is useful for operator self-service.

## Findings

### 1) Service boundaries are too broad for long-term maintainability
`Sources/CanaryTranscriber/main.swift` currently contains:
- SwiftUI app bootstrap
- capture target discovery
- ScreenCaptureKit + AVAudioEngine capture controller
- ffmpeg mixing orchestration
- batch process spawning and stdout parsing
- persistent logging helper
- the full embedded Python transcription pipeline as a multiline string

That makes the app hard to test independently and hard to evolve without regressions. The biggest architectural improvement would be to split this into small services/modules, for example:
- `CaptureService`
- `TranscriptionRunner`
- `DependencyManager`
- `PersistentLogStore`
- `ContentViewModel`

This is not a correctness bug today, but it is the main architectural debt.

### 2) Reliability is decent, but observability/error-handling still has some blind spots
The app does a good job validating common failure modes up front, but a few areas remain soft:
- Persistent logging intentionally swallows filesystem write failures, so operators may lose audit history without noticing.
- The batch runner depends on stdout parsing for status. That is fine locally, but there is no structured severity, no counters, and no correlation ID across capture → mix → transcription stages.
- The embedded Python pipeline writes `overlap_duration: 0` into its output payload even though the config carries `overlapDuration`; if overlap is intended as an operational tuning knob, it is not currently observable in outputs.

## Recommendation
No release blocker from an SRE/architecture standpoint for a local desktop app, but I would strongly recommend extracting the transcription runner and capture controller out of `main.swift` before adding more profiles or more capture modes. That will improve testability, reduce accidental coupling, and make future reliability work much easier.

RESULT: PASS
