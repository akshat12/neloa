#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

if [ -z "${NELOA_EXECUTABLE_PATH:-}" ]; then
    swift build -c release --product Neloa
    BIN_DIR=$(swift build -c release --show-bin-path)
    EXECUTABLE_PATH="$BIN_DIR/Neloa"
else
    EXECUTABLE_PATH=$NELOA_EXECUTABLE_PATH
fi

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "error: Neloa executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

sh "$PROJECT_DIR/scripts/build-icon.sh"
APP_DIR="$PROJECT_DIR/dist/Neloa.app"
LEGACY_APP_DIR="$PROJECT_DIR/dist/Humana.app"
ENTITLEMENTS="$PROJECT_DIR/Resources/Neloa.entitlements"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -n "${NELOA_APP_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NELOA_APP_VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [ -n "${NELOA_BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NELOA_BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/Neloa"
chmod 755 "$APP_DIR/Contents/MacOS/Neloa"
find "$APP_DIR/Contents/MacOS" -maxdepth 1 -type f -name '*.cstemp' -delete
touch "$APP_DIR"
LOCAL_SIGN_IDENTITY=${NELOA_LOCAL_CODE_SIGN_IDENTITY:-Neloa Local Development}
if [ "${NELOA_FORCE_ADHOC:-0}" = "1" ]; then
    SIGN_IDENTITY=-
    SIGNING_MODE=ad-hoc
elif [ -n "${NELOA_CODE_SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$NELOA_CODE_SIGN_IDENTITY
    SIGNING_MODE=distribution
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$LOCAL_SIGN_IDENTITY\""; then
    SIGN_IDENTITY=$LOCAL_SIGN_IDENTITY
    SIGNING_MODE=local
else
    SIGN_IDENTITY=-
    SIGNING_MODE=ad-hoc
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    if [ "${NELOA_FORCE_ADHOC:-0}" = "1" ]; then
        echo "warning: creating an unsigned preview with an ad-hoc signature" >&2
    else
        echo "warning: using ad-hoc signing; Screen Recording permission will not survive rebuilds" >&2
        echo "run 'make setup-signing' once to create a stable local identity" >&2
    fi
    codesign --force --deep --sign - \
        --identifier ai.neloa.desktop \
        --requirements '=designated => identifier "ai.neloa.desktop"' \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR"
elif [ "$SIGNING_MODE" = "distribution" ]; then
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp=none \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
fi
rm -rf "$LEGACY_APP_DIR"

echo "$APP_DIR"
