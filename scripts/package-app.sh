#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

swift build -c release --product Neloa
sh "$PROJECT_DIR/scripts/build-icon.sh"
BIN_DIR=$(swift build -c release --show-bin-path)
APP_DIR="$PROJECT_DIR/dist/Neloa.app"
LEGACY_APP_DIR="$PROJECT_DIR/dist/Humana.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/Neloa" "$APP_DIR/Contents/MacOS/Neloa"
chmod 755 "$APP_DIR/Contents/MacOS/Neloa"
touch "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"

echo "$APP_DIR"
