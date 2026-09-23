#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Canary Transcriber.app"
DMG="$ROOT/dist/CanaryTranscriber.dmg"
ZIP="$ROOT/dist/CanaryTranscriber.app.zip"
VOLNAME="Canary Transcriber"
BUILD_ROOT="${TMPDIR:-/tmp}/canary-transcriber-installer"
DMG_DIR="$BUILD_ROOT/dmg-staging"
DMG_WORK="$BUILD_ROOT/CanaryTranscriber.dmg"
ZIP_DIR="$BUILD_ROOT/zip-staging"
ZIP_WORK="$BUILD_ROOT/CanaryTranscriber.app.zip"

"$ROOT/scripts/build-canary-transcriber-app.sh"

rm -rf "$BUILD_ROOT" "$DMG" "$DMG.sha256" "$ZIP" "$ZIP.sha256"
mkdir -p "$DMG_DIR"
# Copy without resource forks / extended attributes so codesign strict verification
# remains valid after the app is placed inside the read-only DMG.
ditto --norsrc --noextattr "$APP" "$DMG_DIR/Canary Transcriber.app"
ln -s /Applications "$DMG_DIR/Applications"
xattr -cr "$DMG_DIR" || true
codesign --verify --deep --strict --verbose=2 "$DMG_DIR/Canary Transcriber.app"

# A simple drag-to-Applications DMG. The app is ad-hoc signed; users may need to approve it
# in macOS Privacy & Security on first launch because it is not notarized.
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -fs APFS \
  -format UDZO \
  "$DMG_WORK"

hdiutil imageinfo "$DMG_WORK" >/dev/null
ditto --norsrc --noextattr "$DMG_WORK" "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"

# Also produce a plain zipped .app as a fallback for users who prefer not to use DMG.
mkdir -p "$ZIP_DIR"
ditto --norsrc --noextattr "$APP" "$ZIP_DIR/Canary Transcriber.app"
(cd "$ZIP_DIR" && zip -qry "$ZIP_WORK" "Canary Transcriber.app")
ditto --norsrc --noextattr "$ZIP_WORK" "$ZIP"
shasum -a 256 "$ZIP" > "$ZIP.sha256"
rm -rf "$BUILD_ROOT"

rm -rf "$DMG_DIR"

echo "Built installer: $DMG"
echo "DMG checksum: $(cat "$DMG.sha256")"
echo "Built zip: $ZIP"
echo "ZIP checksum: $(cat "$ZIP.sha256")"
