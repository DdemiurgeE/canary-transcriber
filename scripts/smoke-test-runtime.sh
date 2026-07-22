#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Sources/CanaryTranscriberLib/TranscriptionViewModel.swift"
PYTHON_BIN="${PYTHON_BIN:-python3}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/canary-runtime-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

export SOURCE TMP_DIR
"$PYTHON_BIN" - <<'PY'
import json
import os
from pathlib import Path

source = Path(os.environ["SOURCE"]).read_text(encoding="utf-8")
start_marker = 'let script = #"""'
end_marker = '"""#'
start = source.find(start_marker)
if start < 0:
    raise SystemExit(f"embedded runtime marker missing: {start_marker}")
start += len(start_marker)
end = source.find(end_marker, start)
if end < 0:
    raise SystemExit(f"embedded runtime marker missing: {end_marker}")
script = source[start:end]
out = Path(os.environ["TMP_DIR"]) / "canary-transcriber-runtime.py"
out.write_text(script, encoding="utf-8")
fixture = Path(os.environ["TMP_DIR"]) / "fixtures.json"
fixture.write_text(json.dumps({
    "files": [],
    "_eventFixtures": [
        {"kind": "batch_start", "total": 1},
        {"kind": "file_started", "path": "fixture.m4a", "index": 1},
        {"kind": "chunk_done", "index": 0, "start": 0.0, "chars": 7},
        {"kind": "file_done", "file": "fixture.m4a", "chars": 7},
        {"kind": "future_kind", "value": 42},
    ],
}, ensure_ascii=False), encoding="utf-8")
print(out)
print(fixture)
PY

RUNTIME="$TMP_DIR/canary-transcriber-runtime.py"
FIXTURE="$TMP_DIR/fixtures.json"
"$PYTHON_BIN" -m py_compile "$RUNTIME"
OUTPUT="$($PYTHON_BIN -u "$RUNTIME" "$FIXTURE")"
printf '%s\n' "$OUTPUT"
grep -F 'CANARY_EVENT' <<<"$OUTPUT" >/dev/null
grep -F 'future_kind' <<<"$OUTPUT" >/dev/null
printf 'Runtime smoke passed.\n'
