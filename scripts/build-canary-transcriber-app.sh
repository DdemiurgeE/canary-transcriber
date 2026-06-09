#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build --product canary-transcriber

APP="$ROOT/dist/Canary Transcriber.app"
BIN="$ROOT/.build/arm64-apple-macosx/debug/canary-transcriber"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/debug/canary-transcriber"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Cannot find built canary-transcriber binary" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleExecutable</key>
    <string>canary-transcriber</string>
    <key>CFBundleIdentifier</key>
    <string>local.canary-transcriber.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Canary Transcriber</string>
    <key>CFBundleDisplayName</key>
    <string>Canary Transcriber</string>
    <key>CFBundleIconFile</key>
    <string>CanaryTranscriber</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Local app</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BIN" "$APP/Contents/MacOS/canary-transcriber"
cp "$ROOT/assets/canary-transcriber/CanaryTranscriber.icns" "$APP/Contents/Resources/CanaryTranscriber.icns"
chmod +x "$APP/Contents/MacOS/canary-transcriber"

xattr -cr "$APP" || true
codesign --force --deep --sign - "$APP" >/dev/null
xattr -cr "$APP" || true
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built: $APP"
