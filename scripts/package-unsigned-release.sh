#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

DEFAULT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
VERSION=${RELEASE_VERSION:-$DEFAULT_VERSION}
BUILD_NUMBER=${NELOA_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)}

case "$VERSION" in
    ''|*[!0-9A-Za-z.-]*)
        echo "error: invalid release version '$VERSION'" >&2
        exit 1
        ;;
esac

case "$BUILD_NUMBER" in
    ''|*[!0-9]*)
        echo "error: build number must contain only digits" >&2
        exit 1
        ;;
esac

UNIVERSAL_DIR="$PROJECT_DIR/.build/unsigned-release"
UNIVERSAL_EXECUTABLE="$UNIVERSAL_DIR/Neloa"
STAGING_DIR="$UNIVERSAL_DIR/staging"
APP_PATH="$STAGING_DIR/Neloa.app"
LOCAL_APP_PATH="$PROJECT_DIR/dist/Neloa.app"
ARM_SCRATCH="$PROJECT_DIR/.build/release-arm64"
INTEL_SCRATCH="$PROJECT_DIR/.build/release-x86_64"

LOCAL_APP_CDHASH_BEFORE=
if [ -d "$LOCAL_APP_PATH" ]; then
    LOCAL_APP_CDHASH_BEFORE=$(codesign -dvvv "$LOCAL_APP_PATH" 2>&1 | sed -n 's/^CDHash=//p')
    if [ -z "$LOCAL_APP_CDHASH_BEFORE" ]; then
        echo "error: could not fingerprint the existing local app at $LOCAL_APP_PATH" >&2
        exit 1
    fi
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$PROJECT_DIR/dist"

swift build -c release \
    --triple arm64-apple-macosx15.0 \
    --scratch-path "$ARM_SCRATCH" \
    --product Neloa
swift build -c release \
    --triple x86_64-apple-macosx15.0 \
    --scratch-path "$INTEL_SCRATCH" \
    --product Neloa

ARM_BIN_DIR=$(swift build -c release --triple arm64-apple-macosx15.0 --scratch-path "$ARM_SCRATCH" --show-bin-path)
INTEL_BIN_DIR=$(swift build -c release --triple x86_64-apple-macosx15.0 --scratch-path "$INTEL_SCRATCH" --show-bin-path)
lipo -create "$ARM_BIN_DIR/Neloa" "$INTEL_BIN_DIR/Neloa" -output "$UNIVERSAL_EXECUTABLE"

NELOA_EXECUTABLE_PATH="$UNIVERSAL_EXECUTABLE" \
NELOA_APP_OUTPUT_PATH="$APP_PATH" \
NELOA_FORCE_ADHOC=1 \
NELOA_APP_VERSION="$VERSION" \
NELOA_BUILD_NUMBER="$BUILD_NUMBER" \
    sh "$PROJECT_DIR/scripts/package-app.sh"

ZIP_NAME="Neloa-$VERSION-macOS-universal-unsigned.zip"
ZIP_PATH="$PROJECT_DIR/dist/$ZIP_NAME"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/Neloa" -verify_arch arm64 x86_64
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
(
    cd "$PROJECT_DIR/dist"
    shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)

VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/neloa-release.XXXXXX")
trap 'rm -rf "$VERIFY_DIR"' EXIT HUP INT TERM
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/Neloa.app"
"$VERIFY_DIR/Neloa.app/Contents/MacOS/Neloa" --self-test

if [ -n "$LOCAL_APP_CDHASH_BEFORE" ]; then
    LOCAL_APP_CDHASH_AFTER=$(codesign -dvvv "$LOCAL_APP_PATH" 2>&1 | sed -n 's/^CDHash=//p')
    if [ "$LOCAL_APP_CDHASH_AFTER" != "$LOCAL_APP_CDHASH_BEFORE" ]; then
        echo "error: unsigned release packaging modified the stable local app" >&2
        exit 1
    fi
fi

echo "$ZIP_PATH"
echo "$ZIP_PATH.sha256"
