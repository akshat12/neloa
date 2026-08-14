#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MASTER="$PROJECT_DIR/Resources/AppIcon-1024.png"
ICONSET="$PROJECT_DIR/.build/Neloa.iconset"

swift "$PROJECT_DIR/scripts/generate-icon.swift" "$MASTER"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

GENERATED_ICNS="$PROJECT_DIR/.build/AppIcon.generated.$$.icns"
if iconutil -c icns "$ICONSET" -o "$GENERATED_ICNS"; then
    mv "$GENERATED_ICNS" "$PROJECT_DIR/Resources/AppIcon.icns"
elif [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    rm -f "$GENERATED_ICNS"
    echo "warning: iconutil rejected the generated iconset; keeping the checked-in AppIcon.icns" >&2
else
    rm -f "$GENERATED_ICNS"
    echo "error: iconutil failed and no checked-in AppIcon.icns is available" >&2
    exit 1
fi
