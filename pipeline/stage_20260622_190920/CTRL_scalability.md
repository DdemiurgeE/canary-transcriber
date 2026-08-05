# Scalability / Performance Review

## Scope
Reviewed the changed files:
- `README.md`
- `Sources/CanaryTranscriber/main.swift`

Also validated the project builds with:
- `swift build --product canary-transcriber`

## What I found
The app is dominated by external work rather than in-process Swift CPU usage:
- ScreenCaptureKit enumeration for app capture selection
- `ffmpeg` normalization and chunking
- MLX / Whisper / Canary inference launched in Python
- Optional diarization via `pyannote`

That means the main scalability pressure is not UI rendering, but repeated process launches and file-system scans around those pipelines.

## Hot paths
### 1) Batch transcription pipeline
The hot path is the embedded Python batch script in `runPython(...)`:
- normalizes each input through `ffmpeg`
- chunks the normalized WAV
- runs one inference call per chunk/segment
- optionally runs diarization first

This is inherently O(files × chunks) and will scale linearly with input length. That is expected, but it makes caching important.

### 2) Model cache check
`checkModelCache()` launches Python and recursively scans the Hugging Face cache directory with `rglob("*.safetensors")`, `rglob("*.bin")`, and `rglob("*.msgpack")`.

This is the biggest avoidable overhead I saw. On a large Hugging Face cache, this can become expensive and it is run as a UI-side status check.

### 3) Capture app enumeration
`loadShareableApplications()` calls `SCShareableContent.excludingDesktopWindows(...)` and `refreshCaptureApps()` can call it again when the user refreshes or starts capture.

This is acceptable for manual refresh, but it is still a relatively expensive system query and could be cached briefly if the UI starts to feel sluggish.

### 4) Output parsing for `mlx_audio_cli`
The CLI path does `sorted(out_dir.rglob("*"))` and then scans all files for transcript content.

For a temp directory this is usually small, but it is still broader than necessary. If the runtime output format is known, a direct expected-path read would be cheaper.

## Caching opportunities
Recommended low-risk improvements if this grows:
- Cache `SCShareableContent` results for a short window instead of re-querying on every refresh/start.
- Cache model cache status per model ID and invalidate only when download status changes.
- Replace recursive cache scanning in `checkModelCache()` with a cheaper existence check against known Hugging Face snapshot paths or metadata.
- Maintain a `Set<String>` of file paths alongside `files` if very large batches are expected; `addAudioPaths()` currently rebuilds the dedupe set from the full list each time.

## Query-plan / indexing note
There is no database access in the changed files, so there are no SQL query plans to analyze.
The closest equivalent is filesystem and cache lookup strategy, and those are currently brute-force rather than indexed/metadata-driven.

## Verification
- `swift build --product canary-transcriber` succeeded.

## Verdict
No blocking scalability issue was found in the changed code.
The main cost centers are expected for an audio transcription app, and the identified optimizations are opportunistic rather than required.

RESULT: PASS