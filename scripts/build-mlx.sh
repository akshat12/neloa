#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${NELOA_MLX_CONFIGURATION:-Debug}
DERIVED_DATA=${NELOA_MLX_DERIVED_DATA:-$PROJECT_DIR/.build/xcode-mlx}

case "$CONFIGURATION" in
    Debug|Release) ;;
    *)
        echo "error: NELOA_MLX_CONFIGURATION must be Debug or Release" >&2
        exit 1
        ;;
esac

sh "$PROJECT_DIR/scripts/check-mlx-toolchain.sh"

cd "$PROJECT_DIR"
NELOA_ENABLE_MLX=1 xcodebuild \
    -scheme Neloa \
    -destination 'platform=macOS' \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=15.0 \
    build

EXECUTABLE_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Neloa"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "error: Xcode did not produce Neloa at $EXECUTABLE_PATH" >&2
    exit 1
fi

RESOURCE_DIRECTORY=$(dirname "$EXECUTABLE_PATH")
if ! find "$RESOURCE_DIRECTORY" -type f -name 'default.metallib' -print -quit | grep -q .; then
    echo "error: Xcode built Neloa without the MLX Metal shader library" >&2
    exit 1
fi

echo "$EXECUTABLE_PATH"
