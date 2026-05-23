#!/usr/bin/env bash
# Builds the kmac-app menu-bar agent into a proper KMac.app bundle.
# A real bundle (not the raw SPM binary) is required for the global Cmd+K
# hotkey: macOS only grants Accessibility trust to identifiable apps, and
# LSUIElement makes it a dockless menu-bar agent.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="KMac.app"
BIN_NAME="KMac"

echo "Building kmac-app ($CONFIG)..."
swift build -c "$CONFIG" --product kmac-app

BIN_PATH=".build/$CONFIG/kmac-app"

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/KMacApp-Info.plist "$APP/Contents/Info.plist"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
chmod +x "$APP/Contents/MacOS/$BIN_NAME"

# Ad-hoc codesign so the bundle has a stable identity for Accessibility trust.
codesign --force --sign - "$APP" 2>/dev/null || echo "warning: codesign skipped"

echo "Built $(pwd)/$APP"
echo "Launch:  open $APP    Install:  cp -r $APP /Applications/"
