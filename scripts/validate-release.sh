#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Canary Transcriber.app"
DMG="$DIST/CanaryTranscriber.dmg"
ZIP="$DIST/CanaryTranscriber.app.zip"

fail() { printf 'Release validation failed: %s\n' "$1" >&2; exit 1; }
[[ -d "$APP" ]] || fail "missing app bundle: $APP"
[[ -x "$APP/Contents/MacOS/canary-transcriber" ]] || fail "missing executable"
[[ -f "$APP/Contents/Info.plist" ]] || fail "missing Info.plist"

region="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$APP/Contents/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$region" == "en" ]] || fail "CFBundleDevelopmentRegion must be en, got $region"
[[ -n "$version" ]] || fail "empty CFBundleShortVersionString"
[[ -n "$build" ]] || fail "empty CFBundleVersion"
if [[ -n "${EXPECTED_VERSION:-}" && "$version" != "$EXPECTED_VERSION" ]]; then
  fail "expected version $EXPECTED_VERSION, got $version"
fi

codesign --verify --deep --verbose=2 "$APP" >/dev/null || fail "codesign verification failed"
for asset in "$DMG" "$ZIP" "$DMG.sha256" "$ZIP.sha256"; do
  [[ -f "$asset" ]] || fail "missing release asset: $asset"
done
(cd "$DIST" && shasum -a 256 -c "$(basename "$DMG.sha256")" >/dev/null) || fail "DMG checksum mismatch"
(cd "$DIST" && shasum -a 256 -c "$(basename "$ZIP.sha256")" >/dev/null) || fail "ZIP checksum mismatch"

if [[ -n "${CANARY_OUTPUT_DIR:-}" ]]; then
  [[ -d "$CANARY_OUTPUT_DIR" ]] || fail "CANARY_OUTPUT_DIR does not exist"
  python3 - "$CANARY_OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
json_files = list(root.glob('*.canary.json'))
if not json_files:
    raise SystemExit('no .canary.json output found')
for path in json_files:
    data = json.loads(path.read_text(encoding='utf-8'))
    required = {'audio', 'profile', 'runtime', 'model', 'language', 'text', 'chunks'}
    missing = required - data.keys()
    if missing:
        raise SystemExit(f'{path}: missing fields: {sorted(missing)}')
print(f'Validated {len(json_files)} transcription JSON output(s).')
PY
fi

printf 'Release validation passed: version=%s build=%s\n' "$version" "$build"
