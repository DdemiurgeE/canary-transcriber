# Runtime profiles

Canary Transcriber keeps profile selection read-only at model level. Choose `Profile`; app supplies matching runtime, model, language, and default chunk size.

| Profile | Runtime | Model | Best use |
|---|---|---|---|
| `fast-parakeet-v3` | `mlx_audio_cli` | `mlx-community/parakeet-tdt-0.6b-v3` | Fast Russian STT |
| `fast-whisper-turbo` | `mlx_whisper` | `mlx-community/whisper-large-v3-turbo` | Fast Whisper-compatible STT |
| `accurate-whisper-large-v3` | `mlx_whisper` | `mlx-community/whisper-large-v3-mlx` | Quality-first baseline |
| `multilingual-canary-v2` | `mlx_audio_cli` | `CogniSoftOrg/canary-1b-v2-mlx-bf16` | Multilingual European STT |
| `realtime-voxtral-mini` | `mlx_audio_cli` | `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` | Realtime-oriented model in batch mode |

## Russian Canary v2

Canary v2 requires both CLI language selection and generation kwargs:

```text
--language ru
--gen-kwargs {"source_lang":"ru","target_lang":"ru"}
```

This keeps Russian as ASR target instead of silently using English defaults or translation.

## Runtime packages

```bash
~/venvs/canary-mlx/bin/python -c "import mlx_audio"
~/venvs/canary-mlx/bin/python -c "import mlx_whisper"
~/venvs/canary-mlx/bin/python -c "import canary_mlx"
```

Install packages needed by selected profiles:

```bash
~/venvs/canary-mlx/bin/python -m pip install canary-mlx mlx-whisper 'mlx-audio[stt]' huggingface_hub
```

## Long recordings

Input audio is normalized to 16 kHz mono WAV and processed in fixed chunks. Default chunk duration is 30 seconds with 2 seconds overlap. For Metal memory failures, use 15 or 10 seconds. Empty chunks are omitted; per-chunk details remain in `.canary.json`.

## Outputs

Each source produces `.canary.txt`, `.canary.json`, and `.canary.md`. JSON preserves profile/runtime/model/language, chunk records, errors, and optional diarization data. Markdown becomes a meeting workspace when usable speaker segments exist.
