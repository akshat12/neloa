#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARTIFACT_DIR="$PROJECT_DIR/.build/mlx-artifacts"
ARCHIVE="$ARTIFACT_DIR/Cmlx-0.31.6.xcframework.zip"
METALLIB="$ARTIFACT_DIR/mlx.metallib"
EXPECTED_SHA256="a202bf1dcfe1e64404adabfeb5eb363332e3a6221d18e4289ca0663fa3ab86c9"
DOWNLOAD_URL="https://github.com/ml-explore/mlx-swift/releases/download/0.31.6/Cmlx.xcframework.zip"
ARCHIVE_MEMBER="Cmlx.xcframework/macos-arm64_x86_64/Cmlx.framework/Versions/A/Resources/default.metallib"

mkdir -p "$ARTIFACT_DIR"

archive_is_valid() {
    [ -f "$ARCHIVE" ] && [ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" = "$EXPECTED_SHA256" ]
}

if ! archive_is_valid; then
    TEMP_ARCHIVE=$(mktemp "$ARTIFACT_DIR/Cmlx.download.XXXXXX")
    trap 'rm -f "$TEMP_ARCHIVE"' EXIT HUP INT TERM
    curl -fL --retry 3 --connect-timeout 30 "$DOWNLOAD_URL" -o "$TEMP_ARCHIVE"
    ACTUAL_SHA256=$(shasum -a 256 "$TEMP_ARCHIVE" | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "error: downloaded MLX shader artifact failed its checksum" >&2
        exit 1
    fi
    mv "$TEMP_ARCHIVE" "$ARCHIVE"
    trap - EXIT HUP INT TERM
fi

TEMP_METALLIB=$(mktemp "$ARTIFACT_DIR/mlx.metallib.XXXXXX")
trap 'rm -f "$TEMP_METALLIB"' EXIT HUP INT TERM
unzip -p "$ARCHIVE" "$ARCHIVE_MEMBER" > "$TEMP_METALLIB"
if [ ! -s "$TEMP_METALLIB" ]; then
    echo "error: official MLX artifact did not contain the macOS Metal shader library" >&2
    exit 1
fi
mv "$TEMP_METALLIB" "$METALLIB"
trap - EXIT HUP INT TERM

echo "$METALLIB"

