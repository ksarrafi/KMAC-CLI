#!/usr/bin/env bash
# Builds the kmac-app menu-bar agent and installs it as /Applications/KMac.app.
#
# The bundle is assembled in a temp staging dir and copied to /Applications, so
# no KMac.app is ever left under ~/Projects — that matters because Spotlight
# indexes any .app in the home tree and would show duplicate "KMac" entries.
#
# A real bundle (not the raw SPM binary) is also required for the global Cmd+K
# hotkey: macOS only grants Accessibility trust to identifiable apps, and
# LSUIElement makes it a dockless menu-bar agent.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
BIN_NAME="KMac"
DEST="/Applications/KMac.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Building kmac-app ($CONFIG)..."
swift build -c "$CONFIG" --product kmac-app
BIN_PATH=".build/$CONFIG/kmac-app"

STAGE="$(mktemp -d)/$BIN_NAME.app"
echo "Assembling bundle in staging..."
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp Resources/KMacApp-Info.plist "$STAGE/Contents/Info.plist"
cp "$BIN_PATH" "$STAGE/Contents/MacOS/$BIN_NAME"
chmod +x "$STAGE/Contents/MacOS/$BIN_NAME"
codesign --force --sign - "$STAGE" 2>/dev/null || echo "warning: codesign skipped"

echo "Installing to $DEST (stopping any running instance)..."
pkill -f "$DEST/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
rm -rf "$DEST"
cp -r "$STAGE" "$DEST"
rm -rf "$(dirname "$STAGE")"

# Keep LaunchServices/Spotlight pointing at exactly one KMac.app.
"$LSREG" -f "$DEST" 2>/dev/null || true

echo "Installed $DEST"
echo "Launch:  open \"$DEST\"   (or Spotlight: type 'kmac')"
