# Speaker Diarization (Различение собеседников) — Plan

## Current State

The app transcribes audio files by:
1. Normalizing to 16 kHz mono PCM WAV via ffmpeg
2. Splitting into fixed 30-second chunks
3. Transcribing each chunk independently via the selected MLX runtime
4. Joining all chunk texts in sequence
5. Writing `.canary.txt`, `.canary.json`, `.canary.md`

**Output currently has NO speaker labels.** All text is flat, one paragraph per chunk.

## Available Resources

- **venv:** `/Users/pavelpalnikov/venvs/canary-mlx/bin/python`
- **PyTorch 2.12.0** with MPS (Metal) support ✅
- **librosa 0.11.0** ✅
- **scikit-learn** ✅
- **pyannote.audio 4.0.4** ✅ (just installed)
- **torchaudio 2.11.0** ✅ (just installed)

## Potential Approaches

### Approach A: pyannote.audio — gold standard (⭐ recommended)

**What:** Use `pyannote/speaker-diarization-3.1` pipeline for full diarization.

**How:**
1. Pre-process audio with diarization → segments like `[(0.0-2.3, SPEAKER_00), (2.3-5.1, SPEAKER_01), ...]`
2. Split audio by speaker segments (not fixed chunks)
3. Transcribe each segment with the existing MLX pipeline
4. Output with speaker labels:
   ```
   [SPEAKER_00]: Привет, как дела?
   [SPEAKER_01]: Всё отлично, спасибо!
   ```

**Quality:** Highest — uses dedicated speaker embedding model + clustering (ECAPA-TDNN + Bayes clustering). Handles 2+ speakers, overlapping speech detection.

**Dependencies:** `pyannote/speaker-diarization-3.1` is gated on HuggingFace. Need to:
1. Visit https://huggingface.co/pyannote/speaker-diarization-3.1
2. Click "Agree and access repository"
3. Then use existing `hf_...` token

**Drawback:** ~2 GB model download on first run, ~30-60 sec for 1 hour audio on MPS.

### Approach B: Custom librosa + sklearn clustering (no HF gate)

**What:** Build lightweight diarization from audio features only.

**How:**
1. Voice Activity Detection (energy-based via librosa)
2. Extract MFCC + spectral features per speech frame
3. Cluster frames with AgglomerativeClustering (cosine distance)
4. Merge adjacent same-cluster frames into speaker segments
5. Transcribe each segment

**Quality:** Medium. Works well for clean 2-speaker recordings. Struggles with >2 speakers, cross-talk, or noisy environments.

**Dependencies:** Already installed (librosa + sklearn). Zero model downloads.

**Drawback:** Less accurate, sensitive to audio quality, no dedicated speaker embedding model.

### Approach C: SpeechBrain speaker embeddings

**What:** Use `speechbrain/spkrec-ecapa-voxceleb` for proper speaker embeddings, then cluster.

**How:**
1. Run VAD to detect speech segments
2. Extract ECAPA-TDNN speaker embeddings per segment
3. Cluster embeddings with sklearn
4. Assign speaker labels
5. Transcribe each segment

**Quality:** High — uses proper speaker embedding model. Between Approach A and B.

**Dependencies:** `pip install speechbrain` (~200 MB). Model downloads ~500 MB. No HF gate on speechbrain models (open access).

### Approach D: LLM-based post-hoc diarization

**What:** After transcription, use a local LLM (MLX) to analyze transcript and label speakers based on conversation structure.

**How:**
1. Transcribe normally (current code)
2. Pass transcript to mlx-lm with a prompt: "Analyze this meeting transcript and insert speaker labels..."
3. LLM infers speaker turns

**Quality:** Low to Medium. LLM guesses speakers from content context. No acoustic evidence. Can hallucinate wrong speaker assignments. But very lightweight integration.

**Dependencies:** mlx-lm (already in venv). Would need a local model download (~4-8 GB for a reasonable 7B model).

## Proposed Architecture Change

For any approach, the core change is in the embedded Python script in `main.swift`:

```
Before:  normalize → fixed chunk → transcribe → join texts
After:   normalize → diarize → segment by speaker → transcribe each segment → label texts
```

The `.canary.json` output gets a new `speakers` top-level field:

```json
{
  "audio": "...",
  "profile": "multilingual-canary-v2",
  "diarization": {
    "method": "pyannote.audio-v3.1",
    "segments": [
      {"speaker": "SPEAKER_00", "start": 0.0, "end": 2.3, "text": "Привет, как дела?"},
      {"speaker": "SPEAKER_01", "start": 2.3, "end": 5.1, "text": "Всё отлично, спасибо!"}
    ]
  },
  "text": "[SPEAKER_00]: Привет, как дела?\n[SPEAKER_01]: Всё отлично, спасибо!",
  "chunks": [...]
}
```

The `.canary.md` gets speaker labels in the body:

```markdown
---
source: meeting.m4a
diarization: pyannote.audio-v3.1
---

# Transcript: meeting.m4a

**SPEAKER_00**: Привет, как дела?

**SPEAKER_01**: Всё отлично, спасибо!
```

## Integration Plan

The diarization step happens in the embedded Python BEFORE chunk transcription:

```
make_wav_chunks() → run diarization on normalized WAV →
  segment WAV into speaker-homogeneous pieces →
  transcribe each piece with existing make_transcriber() →
  label output with speaker tags
```

Key considerations:
- Diarization is profile-independent (same diarization for any MLX runtime)
- Can be toggled on/off in UI (add a "Speaker diarization" checkbox in Settings)
- Should cache diarization results per audio file (re-transcribe with same speaker segments)
- The `language` setting must still flow through to ASR (source_lang/target_lang for Canary v2)
