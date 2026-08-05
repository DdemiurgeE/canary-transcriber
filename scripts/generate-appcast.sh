#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: generate-appcast.sh <version> [github-release-tag]}"
TAG="${2:-v$VERSION}"
ZIP="$ROOT/dist/CanaryTranscriber.app.zip"
APP_PLIST="$ROOT/dist/Canary Transcriber.app/Contents/Info.plist"
APPCAST="$ROOT/docs/appcast.xml"

[[ -f "$ZIP" ]] || { echo "missing $ZIP — run scripts/build-installer-dmg.sh first" >&2; exit 1; }
[[ -f "$APP_PLIST" ]] || { echo "missing $APP_PLIST — run scripts/build-installer-dmg.sh first" >&2; exit 1; }

SIGN_UPDATE="$(find "$ROOT/.build/artifacts" -type f -perm +111 -name sign_update 2>/dev/null | head -1)"
[[ -n "$SIGN_UPDATE" ]] || { echo "sign_update not found under .build/artifacts — run 'swift build' once to fetch the Sparkle artifact" >&2; exit 1; }

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PLIST")"
[[ "$PLIST_VERSION" == "$VERSION" ]] || { echo "requested version $VERSION does not match built app version $PLIST_VERSION" >&2; exit 1; }

DOWNLOAD_URL="https://github.com/DdemiurgeE/canary-transcriber/releases/download/${TAG}/CanaryTranscriber.app.zip"
ENCLOSURE_ATTRS="$("$SIGN_UPDATE" "$ZIP")"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

python3 - "$APPCAST" "$VERSION" "$BUILD" "$MIN_OS" "$DOWNLOAD_URL" "$ENCLOSURE_ATTRS" "$PUB_DATE" <<'PY'
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

appcast_path, version, build, min_os, download_url, enclosure_attrs, pub_date = sys.argv[1:8]

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

path = Path(appcast_path)
if path.exists():
    tree = ET.parse(path)
    root = tree.getroot()
    channel = root.find("channel")
else:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Canary Transcriber Changelog"
    ET.SubElement(channel, "link").text = "https://ddemiurgee.github.io/canary-transcriber/appcast.xml"
    ET.SubElement(channel, "description").text = "Most recent changes for Canary Transcriber."
    ET.SubElement(channel, "language").text = "en"
    tree = ET.ElementTree(root)

# Drop any existing item for this version so re-running is idempotent.
for item in list(channel.findall("item")):
    sv = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
    if sv is not None and sv.text == version:
        channel.remove(item)

item = ET.Element("item")
ET.SubElement(item, "title").text = f"Version {version}"
ET.SubElement(item, "pubDate").text = pub_date
ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build
ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = min_os

attrs = dict(re.findall(r'([\w:]+)="([^"]*)"', enclosure_attrs))
enclosure = ET.SubElement(item, "enclosure")
enclosure.set("url", download_url)
enclosure.set("type", "application/octet-stream")
for key, value in attrs.items():
    enclosure.set(key, value)

# Newest item first: re-append remaining (older) items after the new one.
older_items = channel.findall("item")
for existing in older_items:
    channel.remove(existing)
channel.append(item)
for existing in older_items:
    channel.append(existing)

ET.indent(tree, space="    ")
tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"Updated {path} with version {version} (build {build}).")
PY
