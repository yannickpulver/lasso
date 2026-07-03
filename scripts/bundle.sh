#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
BIN=".build/apple/Products/Release/Lasso"
[ -f "$BIN" ] || BIN=".build/release/Lasso"
[ -f "$BIN" ] || { echo "Release binary not found. Run: swift build -c release"; exit 1; }

APP="dist/Lasso.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lasso"
cp assets/icon.icns "$APP/Contents/Resources/icon.icns"
sed "s/__VERSION__/$VERSION/g" assets/Info.plist > "$APP/Contents/Info.plist"
echo "Built $APP (v$VERSION)"
