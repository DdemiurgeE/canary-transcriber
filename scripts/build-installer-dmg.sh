#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Canary Transcriber.app"
DMG_DIR="$ROOT/dist/dmg-staging"
DMG="$ROOT/dist/CanaryTranscriber.dmg"
ZIP="$ROOT/dist/CanaryTranscriber.app.zip"
VOLNAME="Canary Transcriber"

"$ROOT/scripts/build-canary-transcriber-app.sh"

rm -rf "$DMG_DIR" "$DMG" "$ZIP" "$ZIP.sha256"
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
  -fs HFS+ \
  -format UDZO \
  "$DMG"

hdiutil imageinfo "$DMG" >/dev/null
shasum -a 256 "$DMG" > "$DMG.sha256"

# Also produce a plain zipped .app as a fallback for users who prefer not to use DMG.
ZIP_DIR="$ROOT/dist/zip-staging"
rm -rf "$ZIP_DIR"
mkdir -p "$ZIP_DIR"
ditto --norsrc --noextattr "$APP" "$ZIP_DIR/Canary Transcriber.app"
(cd "$ZIP_DIR" && zip -qry "$ZIP" "Canary Transcriber.app")
shasum -a 256 "$ZIP" > "$ZIP.sha256"
rm -rf "$ZIP_DIR"

rm -rf "$DMG_DIR"

echo "Built installer: $DMG"
echo "DMG checksum: $(cat "$DMG.sha256")"
echo "Built zip: $ZIP"
echo "ZIP checksum: $(cat "$ZIP.sha256")"
