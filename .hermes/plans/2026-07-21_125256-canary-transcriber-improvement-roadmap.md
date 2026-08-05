# Canary Transcriber Improvement Roadmap

**Goal:** Make Canary Transcriber more reliable for long Russian recordings and meetings, easier to maintain, and safer to release.

**Architecture:** Keep SwiftUI as the macOS shell, but move transcription orchestration, configuration validation, process execution, output writing, and capture services out of the 2,311-line `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`. Keep the embedded Python runtime temporarily, behind a versioned protocol and fixture-based tests; replace it with a standalone runner only after behavior is covered. Treat diarization as an optional pipeline stage with graceful fallback.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, Swift Package Manager, XCTest, AVFoundation, ScreenCaptureKit, `ffmpeg`, Python `mlx-audio`/`mlx-whisper`/`canary-mlx`, `pyannote.audio`, HuggingFace Hub, GitHub Actions.

---

## Current-state constraints

- Repository is at tag `v0.4.0`, commit `b5b6539`.
- Working tree is not clean. Existing changes must be preserved and classified before implementation:
  - modified: `assets/canary-transcriber/Screenshot.png`
  - untracked: `.hermes/`, `AGENTS.md`, `Sources/CanaryTranscriber/SpeakerAliasPersistence.swift`, `pipeline/`
- Main production implementation is concentrated in `Sources/CanaryTranscriberLib/CanaryTranscriber.swift` (2,311 lines).
- Current test coverage is only 49 lines and covers speaker-alias parsing plus `BatchConfig` Codable round-trip.
- `Package.swift` already contains `CanaryTranscriberCore`, `CanaryTranscriber`, `CanaryTranscriberApp`, and one test target; use this structure instead of adding a second app architecture.
- README contains stale UI guidance: Russian capture labels, editable model/runtime instructions, and old layout wording. UI standards require English-only labels and read-only model selection.

## Priority order

1. Regression safety and clean project boundaries.
2. Transcription correctness and recoverability.
3. Meeting/diarization quality.
4. Capture reliability.
5. UI/UX polish.
6. Release engineering and distribution.

---

## Phase 0: Baseline and scope lock

### Task 0.1: Record baseline

**Files:** Create `.hermes/plans/baseline-canary-transcriber.md` only if needed.

- Run `git status --short`, `swift test`, and `swift build --product canary-transcriber`.
- Record failures separately from pre-existing dirty files.
- Do not stage, delete, reset, or modify existing user-owned changes.

**Verification:** Baseline commands and their real output are recorded before code changes.

### Task 0.2: Classify untracked work

**Files:** `pipeline/`, `Sources/CanaryTranscriber/SpeakerAliasPersistence.swift`, `AGENTS.md`, `.hermes/`.

- Inspect each path.
- Decide whether each belongs in the product, belongs in local tooling, or should remain untracked.
- Add only deliberate product paths to `.gitignore`/the repository later.

**Verification:** No user-owned file is silently overwritten or swept into a commit.

---

## Phase 1: Extract testable core behavior

### Task 1.1: Define validated configuration types

**Files:**
- Create: `Sources/CanaryTranscriberCore/TranscriptionConfiguration.swift`
- Modify: `Sources/CanaryTranscriberCore/CanaryTranscriberCore.swift`
- Test: `Tests/CanaryTranscriberTests/TranscriptionConfigurationTests.swift`

Add typed validation for:
- non-empty input paths;
- supported runtime/profile combinations;
- positive chunk duration;
- non-negative overlap smaller than chunk duration;
- valid speaker count or automatic speaker count;
- existing/executable Python path and `ffmpeg` path at integration boundary.

Keep `BatchConfig` Codable-compatible so existing JSON handoff remains stable.

**TDD:** Add failing tests for valid config, invalid duration, invalid overlap, invalid speaker count, and empty file list; implement minimal validator; run `swift test --filter TranscriptionConfigurationTests`.

### Task 1.2: Extract output naming and metadata

**Files:**
- Create: `Sources/CanaryTranscriberCore/TranscriptionOutputs.swift`
- Test: `Tests/CanaryTranscriberTests/TranscriptionOutputsTests.swift`

Move deterministic output-path generation, source-name sanitization, ISO date handling, and frontmatter field construction into pure Swift functions. Preserve `.canary.txt`, `.canary.json`, and `.canary.md` schemas.

**Verification:** Tests cover Unicode filenames, dots/spaces, output-folder mode, source-adjacent mode, and collision behavior.

### Task 1.3: Extract speaker workspace formatting

**Files:**
- Create: `Sources/CanaryTranscriberCore/MeetingWorkspace.swift`
- Modify: `Sources/CanaryTranscriberCore/CanaryTranscriberCore.swift`
- Test: `Tests/CanaryTranscriberTests/MeetingWorkspaceTests.swift`

Move speaker aliases, segment ordering, duration/count summaries, Markdown rendering, and empty-segment fallback out of the embedded Python/UI file. Preserve raw `SPEAKER_XX` labels for traceability.

**Verification:** Tests prove diarized Markdown is non-empty when `.txt` text exists but segment text is absent; plain transcript fallback remains unchanged.

### Task 1.4: Extract event protocol

**Files:**
- Create: `Sources/CanaryTranscriberCore/TranscriptionEvent.swift`
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/TranscriptionEventTests.swift`

Define typed events for batch start, file start, normalization, diarization, chunk progress, output completion, warning, error, cancellation, and batch completion. Keep compatibility parser for existing `CANARY_EVENT` lines.

**Verification:** Malformed event lines become diagnostics, not crashes; progress events map to monotonic UI progress.

---

## Phase 2: Reliable transcription pipeline

### Task 2.1: Introduce a process runner abstraction

**Files:**
- Create: `Sources/CanaryTranscriberCore/ProcessRunning.swift`
- Create: `Sources/CanaryTranscriberLib/ProcessRunner.swift`
- Test: `Tests/CanaryTranscriberTests/ProcessRunnerTests.swift`

Wrap `Process`, stdout/stderr streaming, termination status, cancellation, environment, and PATH setup. Use dependency injection so tests do not launch Python or `ffmpeg`.

**Verification:** Tests cover stdout/stderr interleaving, non-zero exit, cancellation, missing executable, and final partial line.

### Task 2.2: Make batch cancellation safe

**Files:**
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/CancellationTests.swift`

Replace broad process killing with a tracked process tree/PID set. Ensure Stop cancels current work, terminates child processes, removes temporary files, emits one terminal event, and never marks a stopped batch successful.

**Verification:** Fake runner test proves one terminal state only. Manual smoke test uses the test app process, never `pkill` globally.

### Task 2.3: Make per-file failure recoverable

**Files:**
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/BatchResultTests.swift`

Continue batch after one file fails, record structured error in JSON/log, preserve successful outputs, and expose failed/succeeded/stopped counts in UI.

**Verification:** Fixture batch with one missing input and one valid input yields one success, one structured failure, and batch status `completed with errors`.

### Task 2.4: Harden MLX runtime invocation

**Files:**
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Create: `Tests/Fixtures/RuntimeOutput/`
- Test: `Tests/CanaryTranscriberTests/RuntimeInvocationTests.swift`

Centralize command construction. Preserve Canary v2 `--language ru` plus `--gen-kwargs '{"source_lang":"ru","target_lang":"ru"}'`. Separate model download/progress noise from transcript content. Reject empty/invalid runtime output with actionable diagnostics.

**Verification:** Fixture tests assert exact arguments for each profile, especially Russian Canary v2; a real short Russian sample confirms Cyrillic output.

### Task 2.5: Improve long-audio resource control

**Files:**
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/ChunkPlanningTests.swift`

Define chunk planning as pure logic: duration, overlap, final partial chunk, silence/empty chunks, cleanup, and retry policy. Add bounded retry for transient MLX/Metal memory failures with a smaller chunk size, never retrying permanent configuration errors.

**Verification:** Tests cover 0-second/short/final chunks and retry decisions. Manual test runs a long sample and confirms per-chunk progress plus cleanup.

---

## Phase 3: Diarization and meeting workflow

### Task 3.1: Isolate diarization adapter

**Files:**
- Create: `Sources/CanaryTranscriberCore/Diarization.swift`
- Modify: embedded Python in `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/DiarizationTests.swift`

Define a stable segment model and adapter boundary. Validate sorted, non-negative, non-overlapping/overlap-tolerant segments. Keep pyannote optional; absent token, missing consent, short audio, and pipeline errors must fall back to speakerless transcription with a warning.

**Verification:** Fixture JSON tests cover normal segments, zero segments, malformed segments, and fallback.

### Task 3.2: Add diarization progress and caching

**Files:**
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Modify: `Sources/CanaryTranscriberApp/main.swift`
- Test: `Tests/CanaryTranscriberTests/DiarizationProgressTests.swift`

Expose stages: loading model, running diarization, transcribing speaker segments, writing workspace. Cache pyannote initialization for one batch only; never claim persistent speaker identity across files.

**Verification:** UI log shows stage changes; first run explains HuggingFace consent/model download; short audio falls through cleanly.

### Task 3.3: Make alias persistence explicit and testable

**Files:**
- Review/modify: `Sources/CanaryTranscriber/SpeakerAliasPersistence.swift`
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`
- Test: `Tests/CanaryTranscriberTests/SpeakerAliasPersistenceTests.swift`

Choose one persistence owner (`@AppStorage` or dedicated persistence type), avoid duplicate storage keys, trim invalid entries, and keep aliases local to the user. Preserve comments and `=`, `:`, tab separators.

**Verification:** Round-trip test and launch-level manual check prove aliases survive restart without changing raw JSON speaker labels.

---

## Phase 4: App audio capture reliability

### Task 4.1: Extract capture services

**Files:**
- Create: `Sources/CanaryTranscriberLib/AppAudioCaptureController.swift`
- Create: `Sources/CanaryTranscriberLib/MicrophoneRecorder.swift`
- Create: `Sources/CanaryTranscriberLib/AudioMixer.swift`
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`

Move ScreenCaptureKit, AVAudioEngine, and `ffmpeg amix` logic into separate services. Preserve validated architecture: app audio via `SCStream`, mic via `AVAudioEngine` `.caf`, mix after Stop with validated mic-priority filter.

**Verification:** Service-level fake tests cover start/stop/error states; manual capture verifies non-tiny app-only, mic-only, and mixed files.

### Task 4.2: Improve permission and device diagnostics

**Files:**
- Modify: capture services and UI
- Test: `Tests/CanaryTranscriberTests/CaptureDiagnosticsTests.swift`

Use English-only user-visible errors. Detect denied Screen Recording/Microphone permissions, missing app target, unavailable microphone, zero-frame mic output, and tiny mixed output. Include exact next action in each message.

**Verification:** Permission-denied paths produce actionable logs and no false success event.

---

## Phase 5: UI and documentation consistency

### Task 5.1: Split SwiftUI views from state/orchestration

**Files:**
- Create: `Sources/CanaryTranscriberLib/Views/SettingsView.swift`
- Create: `Sources/CanaryTranscriberLib/Views/FilesView.swift`
- Create: `Sources/CanaryTranscriberLib/Views/AppAudioCaptureView.swift`
- Create: `Sources/CanaryTranscriberLib/Views/LogView.swift`
- Create: `Sources/CanaryTranscriberLib/TranscriptionViewModel.swift`
- Modify: `Sources/CanaryTranscriberLib/CanaryTranscriber.swift`

Keep UI state in an observable view model and make `ContentView` composition-only. Preserve compact English UI, icon-only capture buttons with `.fastTooltip()`, read-only model field, and no redundant header text.

**Verification:** `swift build --product canary-transcriber`; manual UI check confirms labels, disabled states, progress, Stop, Clear logs, Open output, and drag/drop.

### Task 5.2: Refresh README and release docs

**Files:**
- Modify: `README.md`
- Create: `docs/testing.md`
- Create: `docs/runtime-profiles.md`

Remove stale Russian capture labels and editable-model instructions. Document profile matrix, Russian Canary v2 behavior, diarization consent/limitations, output schema, troubleshooting, and verified test commands.

**Verification:** Search README for mixed-language UI labels and contradictory editable fields; both checks return no stale matches.

---

## Phase 6: Release quality

### Task 6.1: Add CI quality gates

**Files:**
- Modify/create: `.github/workflows/ci.yml`
- Modify: `Package.swift` only if needed

Run `swift test`, `swift build --product canary-transcriber`, formatting/static checks, and embedded-script syntax validation extracted from Swift raw strings. Keep runtime MLX/pyannote smoke tests opt-in on an Apple Silicon runner.

**Verification:** CI passes on a clean checkout and reports failures with stage names.

### Task 6.2: Add fixture and manual smoke harness

**Files:**
- Create: `Tests/Fixtures/README.md`
- Create: `scripts/smoke-test-runtime.sh`
- Create: `scripts/validate-release.sh`

Validate app bundle, Info.plist (`CFBundleDevelopmentRegion=en`, version/build), codesign, DMG/ZIP existence, checksums, output schema, and a short real transcription when dependencies exist.

**Verification:** `./scripts/validate-release.sh` passes against `dist/` and fails clearly when an asset/checksum is missing.

### Task 6.3: Release v0.5.0 only after gates pass

**Files:** `scripts/build-canary-transcriber-app.sh`, release notes, generated `dist/` assets.

- Fetch tags/releases first.
- Increment `CFBundleShortVersionString` and build number.
- Stage only intended product files.
- Run `swift test`, build, installer, validation, then create release assets.

**Verification:** GitHub Actions is green; DMG, ZIP, and both SHA-256 files exist; release notes list known diarization limitations.

---

## Definition of done

- Core behavior has unit tests beyond alias/config serialization.
- Python/`ffmpeg` processes are injectable, cancellable, and produce typed events.
- One failed file does not destroy successful batch outputs.
- Russian Canary v2 remains explicitly `ru -> ru`.
- Long-audio and Metal memory failures have visible progress and bounded recovery.
- Diarization fallback never creates false speaker success or blank Markdown.
- App audio capture validates all generated files and permissions.
- UI and README are consistently English and match actual behavior.
- Clean checkout builds/tests; release validation passes before publishing.
- Existing untracked user work is preserved and intentionally classified.

## Recommended first implementation slice

Start with Phase 1, Tasks 1.1–1.4. This gives high leverage without changing user-facing behavior, reduces risk in the monolithic file, and creates test seams for every later phase. Do not begin release work or broad UI refactoring before this regression layer exists.
