# Speaker Diarization — Implementation Notes

Branch: `feature/speaker-diarization`

## Current implementation

Speaker diarization uses `pyannote/speaker-diarization-3.1` and is toggled in Settings:

- Checkbox: `Speaker diarization (pyannote)`
- Field: `Speakers` — default `2`, passed to pyannote as `num_speakers=2`
  - Leave empty for auto-detection
  - Use `2` for typical calls with two people when auto collapses voices into one speaker
  - Use `3`, `4`, etc. when expected

## Why v1 was not good enough

The first version ran pyannote but still transcribed fixed 30-second chunks, then assigned each whole chunk to the speaker with maximum overlap. This loses speaker changes inside a chunk. For example, if a woman and a man speak in the same 30-second chunk, only the dominant speaker label survives.

## Improved architecture

The current version uses diarization segments as the transcription units:

```text
normalize input → pyannote diarization → merge/split speaker segments → cut segment WAVs → transcribe each segment → label output
```

Details:

1. `make_wav_chunks()` still normalizes audio to `normalized.wav` and prepares fallback chunks.
2. `make_diarizer()` loads pyannote once per batch and runs on MPS when available.
3. `speakerCount` from UI is passed as `num_speakers=N` when provided.
4. Raw diarization segments are merged only when:
   - same speaker,
   - small gap (`<=0.8s`),
   - merged duration stays under `Chunk sec`.
5. Long same-speaker regions are split to `Chunk sec` so ASR runtime remains stable.
6. Each merged speaker segment is extracted with ffmpeg and transcribed separately.

## Output

`.canary.txt` and `.canary.md` body:

```text
[SPEAKER_00]: ...
[SPEAKER_01]: ...
```

`.canary.json` includes:

- `diarization: true`
- `speaker_count: 2` (or null for auto)
- `diarization_segments`: raw pyannote segments
- `transcription_segments`: merged/split speaker segments actually sent to ASR
- `chunks[]`: per-transcribed-segment records with `speaker`, `start`, `end`, `text`

## Known limitations

- `SPEAKER_00` / `SPEAKER_01` are cluster labels, not stable identities across files.
- If pyannote auto-detection collapses speakers, force `Speakers=2` or expected count.
- Very short speaker turns may still be missed or merged by pyannote.
- Cross-talk / overlapped speech remains hard.
- Segment-level ASR can be slower because it may run more STT calls than fixed chunks.

## Verification performed

- `swift build --product canary-transcriber` succeeds.
- Embedded Python extracted from `main.swift` compiles via `python -m py_compile`.
- `pyannote/speaker-diarization-3.1` loads on MPS.
- On a real 120s sample:
  - auto mode returned one speaker;
  - forced `num_speakers=2` returned `SPEAKER_00` and `SPEAKER_01`, confirming the `Speakers` control changes diarization behavior.
- `./scripts/build-installer-dmg.sh` succeeds and regenerates app, DMG, ZIP, and checksums.
