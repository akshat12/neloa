#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

swift build -c release --product Humana
sh "$PROJECT_DIR/scripts/build-icon.sh"
BIN_DIR=$(swift build -c release --show-bin-path)
APP_DIR="$PROJECT_DIR/dist/Humana.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/Humana" "$APP_DIR/Contents/MacOS/Humana"
chmod 755 "$APP_DIR/Contents/MacOS/Humana"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
