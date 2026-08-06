#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build --product canary-transcriber

APP="$ROOT/dist/Canary Transcriber.app"
BUILD_DIR="$ROOT/.build/arm64-apple-macosx/debug"
BIN="$BUILD_DIR/canary-transcriber"
if [[ ! -x "$BIN" ]]; then
  BUILD_DIR="$ROOT/.build/debug"
  BIN="$BUILD_DIR/canary-transcriber"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Cannot find built canary-transcriber binary" >&2
  exit 1
fi
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Cannot find Sparkle.framework next to the built binary at $SPARKLE_FRAMEWORK" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
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
    <string>0.7.0</string>
    <key>CFBundleVersion</key>
    <string>9</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Canary Transcriber захватывает аудио выбранного приложения для локальной транскрипции.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Canary Transcriber записывает ваш микрофон вместе со звуком выбранного приложения для транскрипции встреч.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local app</string>
    <key>SUFeedURL</key>
    <string>https://ddemiurgee.github.io/canary-transcriber/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>l2mgkExreHN0q006vLNTXqQeUrgEcouFLB35fTnASoA=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BIN" "$APP/Contents/MacOS/canary-transcriber"
cp "$ROOT/assets/canary-transcriber/CanaryTranscriber.icns" "$APP/Contents/Resources/CanaryTranscriber.icns"
chmod +x "$APP/Contents/MacOS/canary-transcriber"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto --norsrc --noextattr "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/canary-transcriber"

cleanup_xattrs() {
  local target="$1"
  xattr -cr "$target" 2>/dev/null || true
  # xattr -r's own recursion misses some files inside Sparkle.framework (symlinked
  # Versions/Current tree) even after -cr, which then trips codesign with "resource
  # fork, Finder information, or similar detritus not allowed". Walk every file
  # explicitly as a second pass to be sure.
  find "$target" -print0 | xargs -0 xattr -c 2>/dev/null || true
}

cleanup_xattrs "$APP"
codesign --force --deep --sign - "$APP" >/dev/null
cleanup_xattrs "$APP"
codesign --verify --deep --verbose=2 "$APP"

echo "Built: $APP"
